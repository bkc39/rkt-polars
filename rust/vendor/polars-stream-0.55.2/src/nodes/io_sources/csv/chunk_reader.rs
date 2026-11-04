use std::iter::Iterator;
use std::sync::Arc;

use polars_core::prelude::{DataType, Field};
use polars_core::schema::{SchemaExt, SchemaRef};
use polars_error::{PolarsResult, polars_bail, polars_warn};
use polars_io::prelude::_csv_read_internal::{
    NullValuesCompiled, cast_columns, prepare_csv_schema, read_chunk,
};
use polars_io::prelude::builder::validate_utf8;
use polars_io::prelude::{CsvEncoding, CsvParseOptions, CsvReadOptions};

use super::{CHECK_ONLY, NO_SLICE, SLICE_ENDED};
use crate::nodes::compute_node_prelude::*;

#[derive(Default)]
pub(super) struct ChunkReader {
    reader_schema: SchemaRef,
    parse_options: Arc<CsvParseOptions>,
    fields_to_cast: Vec<Field>,
    ignore_errors: bool,
    projection: Vec<usize>,
    /// The columns parsed for a `CHECK_ONLY` chunk, whose rows are not emitted.
    check_projection: Vec<usize>,
    /// The schema of a `CHECK_ONLY` chunk whose check projection substitutes column 0: it
    /// reads that column as a date with errors ignored, so only the row structure is checked.
    check_schema: Option<SchemaRef>,
    null_values: Option<NullValuesCompiled>,
    validate_utf8: bool,
}

impl ChunkReader {
    pub(super) fn try_new(
        options: Arc<CsvReadOptions>,
        mut reader_schema: SchemaRef,
        projection: Vec<usize>,
        check_projection: Vec<usize>,
    ) -> PolarsResult<Self> {
        let mut fields_to_cast: Vec<Field> = options.fields_to_cast.clone();
        prepare_csv_schema(&mut reader_schema, &mut fields_to_cast)?;

        let check_schema = (check_projection != projection).then(|| {
            let mut schema = reader_schema.as_ref().clone();
            schema.set_dtype_at_index(0, DataType::Date);
            Arc::new(schema)
        });

        let parse_options = options.parse_options.clone();

        // Logic from `CoreReader::new()`

        let null_values = parse_options
            .null_values
            .clone()
            .map(|nv| nv.compile(&reader_schema))
            .transpose()?;

        let validate_utf8 = matches!(parse_options.encoding, CsvEncoding::Utf8)
            && reader_schema.iter_fields().any(|f| f.dtype().is_string());

        Ok(Self {
            reader_schema,
            parse_options,
            fields_to_cast,
            ignore_errors: options.ignore_errors,
            projection,
            check_projection,
            check_schema,
            null_values,
            validate_utf8,
        })
    }

    /// The 2nd return value indicates how many rows exist in the chunk.
    pub(super) fn read_chunk(
        &self,
        chunk: &[u8],
        // Number of lines according to CountLines
        n_lines: usize,
        slice: (usize, usize),
        chunk_row_offset: usize,
    ) -> PolarsResult<(DataFrame, usize)> {
        if self.validate_utf8 && !validate_utf8(chunk) {
            polars_bail!(ComputeError: "invalid utf-8 sequence")
        }

        let (projection, schema, ignore_errors, null_values) =
            match (slice == CHECK_ONLY, &self.check_schema) {
                (true, Some(check_schema)) => (&self.check_projection, check_schema, true, None),
                _ => (
                    &self.projection,
                    &self.reader_schema,
                    self.ignore_errors,
                    self.null_values.as_ref(),
                ),
            };

        // If projection is empty create a DataFrame with the correct height by counting the lines.
        let mut df = if projection.is_empty() {
            DataFrame::empty_with_height(n_lines)
        } else {
            read_chunk(
                chunk,
                &self.parse_options,
                schema,
                ignore_errors,
                projection,
                0,       // bytes_offset_thread
                n_lines, // capacity
                null_values,
                usize::MAX,  // chunk_size
                chunk.len(), // stop_at_nbytes
                Some(0),     // starting_point_offset
            )?
        };

        let height = df.height();

        if height != n_lines {
            // Note: in case data is malformed, height is more likely to be correct than n_lines.
            let msg = format!(
                "CSV malformed: expected {} rows, actual {} rows, in chunk starting at row_offset {}, length {}",
                n_lines,
                height,
                chunk_row_offset,
                chunk.len()
            );
            if self.ignore_errors {
                polars_warn!("{msg}");
            } else {
                polars_bail!(ComputeError: msg)
            }
        }

        if slice == CHECK_ONLY && self.check_schema.is_some() {
            df = DataFrame::empty_with_height(0);
        } else if slice != NO_SLICE {
            assert!(slice != SLICE_ENDED);

            df = df.slice(i64::try_from(slice.0).unwrap(), slice.1);
        }

        cast_columns(&mut df, &self.fields_to_cast, false, self.ignore_errors)?;

        Ok((df, height))
    }
}
