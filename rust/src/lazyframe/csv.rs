use crate::prelude::*;
use crate::{
    collect_c_strings, is_pattern, polars_dtype_from_compat, read_path,
    require_path, scan, CompatCsvOptions, CompatDType, PathRules,
};

struct CsvArrays {
    comment_prefix: *const c_char,
    row_index_name: *const c_char,
    null_values: *const *const c_char,
    null_values_len: usize,
    null_columns: *const *const c_char,
    null_markers: *const *const c_char,
    named_nulls_len: usize,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
    overrides_len: usize,
    new_columns: *const *const c_char,
    new_columns_len: usize,
    columns: *const *const c_char,
    columns_len: usize,
    projection: *const usize,
    projection_len: usize,
}

fn decode_string(
    ptr: *const c_char,
    what: &str,
) -> PolarsResult<Option<String>> {
    if ptr.is_null() {
        return Ok(None);
    }
    let text = unsafe { CStr::from_ptr(ptr) }.to_str().map_err(
        |err| polars_err!(ComputeError: "{} is not valid UTF-8: {}", what, err),
    )?;
    Ok(Some(text.to_string()))
}

fn decode_strings(
    ptrs: *const *const c_char,
    len: usize,
    what: &str,
) -> PolarsResult<Vec<PlSmallStr>> {
    let strings = unsafe { collect_c_strings(ptrs, len) }.ok_or_else(
        || polars_err!(ComputeError: "{} are not valid UTF-8 strings", what),
    )?;
    Ok(strings.into_iter().map(PlSmallStr::from).collect())
}

fn decode_null_values(arrays: &CsvArrays) -> PolarsResult<Option<NullValues>> {
    let every = decode_strings(
        arrays.null_values,
        arrays.null_values_len,
        "null values",
    )?;
    let columns = decode_strings(
        arrays.null_columns,
        arrays.named_nulls_len,
        "null value columns",
    )?;
    let markers = decode_strings(
        arrays.null_markers,
        arrays.named_nulls_len,
        "null values",
    )?;
    polars_ensure!(
        every.is_empty() || columns.is_empty(),
        ComputeError: "null values are given both for every column and by column"
    );
    Ok(if !columns.is_empty() {
        Some(NullValues::Named(
            columns.into_iter().zip(markers).collect(),
        ))
    } else {
        (!every.is_empty()).then_some(NullValues::AllColumns(every))
    })
}

fn decode_overrides(
    names: *const *const c_char,
    dtypes: *const CompatDType,
    len: usize,
) -> PolarsResult<Option<SchemaRef>> {
    if len == 0 {
        return Ok(None);
    }
    let names = decode_strings(names, len, "override names")?;
    polars_ensure!(
        !dtypes.is_null(),
        ComputeError: "override dtypes are null"
    );
    let dtypes = unsafe { std::slice::from_raw_parts(dtypes, len) };
    let fields = names
        .iter()
        .zip(dtypes)
        .map(|(name, dtype)| {
            polars_dtype_from_compat(dtype)
                .map(|dtype| Field::new(name.clone(), dtype))
                .ok_or_else(|| {
                    polars_err!(ComputeError: "unsupported dtype for column {:?}", name)
                })
        })
        .collect::<PolarsResult<Vec<_>>>()?;
    Ok(Some(Arc::new(Schema::from_iter(fields))))
}

#[derive(Clone)]
enum Selection {
    Every,
    Names(Vec<PlSmallStr>),
    Indices(Vec<usize>),
}

fn decode_selection(arrays: &CsvArrays) -> PolarsResult<Selection> {
    let names = decode_strings(arrays.columns, arrays.columns_len, "columns")?;
    let indices = match arrays.projection_len {
        0 => Vec::new(),
        len => {
            polars_ensure!(
                !arrays.projection.is_null(),
                ComputeError: "column indices are null"
            );
            unsafe { std::slice::from_raw_parts(arrays.projection, len) }
                .to_vec()
        }
    };
    Ok(match (names.is_empty(), indices.is_empty()) {
        (true, true) => Selection::Every,
        (false, true) => Selection::Names(names),
        (true, false) => Selection::Indices(indices),
        (false, false) => polars_bail!(
            ComputeError: "columns are given both by name and by index"
        ),
    })
}

#[derive(Clone)]
struct CsvRequest {
    comment_prefix: Option<CommentPrefix>,
    row_index: Option<RowIndex>,
    null_values: Option<NullValues>,
    overrides: Option<SchemaRef>,
    new_columns: Vec<PlSmallStr>,
    selection: Selection,
}

fn comment_prefix(prefix: String) -> CommentPrefix {
    match prefix.as_bytes() {
        [byte] if byte.is_ascii() => CommentPrefix::Single(*byte),
        _ => CommentPrefix::Multi(prefix.into()),
    }
}

fn decode(
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<CsvRequest> {
    Ok(CsvRequest {
        comment_prefix: decode_string(arrays.comment_prefix, "comment prefix")?
            .map(comment_prefix),
        row_index: decode_string(arrays.row_index_name, "row index name")?.map(
            |name| RowIndex {
                name: name.into(),
                offset: options.row_index_offset as IdxSize,
            },
        ),
        null_values: decode_null_values(arrays)?,
        overrides: decode_overrides(
            arrays.override_names,
            arrays.override_dtypes,
            arrays.overrides_len,
        )?,
        new_columns: decode_strings(
            arrays.new_columns,
            arrays.new_columns_len,
            "new column names",
        )?,
        selection: decode_selection(arrays)?,
    })
}

fn encoding(options: &CompatCsvOptions) -> CsvEncoding {
    if options.lossy_utf8 {
        CsvEncoding::LossyUtf8
    } else {
        CsvEncoding::Utf8
    }
}

fn parse_options(
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> CsvParseOptions {
    CsvParseOptions::default()
        .with_separator(options.separator)
        .with_quote_char(options.has_quote_char.then_some(options.quote_char))
        .with_eol_char(options.eol_char)
        .with_comment_prefix(request.comment_prefix.clone())
        .with_encoding(encoding(options))
        .with_null_values(request.null_values.clone())
        .with_missing_is_null(!options.missing_utf8_is_empty_string)
        .with_truncate_ragged_lines(options.truncate_ragged_lines)
        .with_decimal_comma(options.decimal_comma)
        .with_try_parse_dates(options.try_parse_dates)
}

fn read_options(
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> CsvReadOptions {
    CsvReadOptions::default()
        .with_has_header(options.has_header)
        .with_skip_rows(options.skip_rows)
        .with_skip_lines(options.skip_lines)
        .with_skip_rows_after_header(options.skip_rows_after_header)
        .with_n_rows(options.has_n_rows.then_some(options.n_rows))
        .with_infer_schema_length(
            options
                .has_infer_schema_length
                .then_some(options.infer_schema_length),
        )
        .with_ignore_errors(options.ignore_errors)
        .with_raise_if_empty(options.raise_if_empty)
        .with_row_index(request.row_index.clone())
        .with_schema_overwrite(request.overrides.clone())
        .with_parse_options(parse_options(options, request))
}

fn lazy_reader(
    path: &str,
    options: &CompatCsvOptions,
    read: CsvReadOptions,
) -> LazyCsvReader {
    let parse = read.get_parse_options();
    LazyCsvReader::new(path.into())
        .with_glob(options.glob)
        .with_has_header(read.has_header)
        .with_skip_rows(read.skip_rows)
        .with_skip_lines(read.skip_lines)
        .with_skip_rows_after_header(read.skip_rows_after_header)
        .with_n_rows(read.n_rows)
        .with_infer_schema_length(read.infer_schema_length)
        .with_ignore_errors(read.ignore_errors)
        .with_raise_if_empty(read.raise_if_empty)
        .with_row_index(read.row_index)
        .with_dtype_overwrite(read.schema_overwrite)
        .map_parse_options(|_| (*parse).clone())
}

fn header_names(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<Schema> {
    let unnamed = CsvRequest {
        null_values: None,
        ..request.clone()
    };
    let rows_read = if options.has_header {
        Some(0)
    } else {
        options
            .has_infer_schema_length
            .then_some(options.infer_schema_length)
    };
    let header = CsvReadOptions::default()
        .with_has_header(options.has_header)
        .with_skip_rows(options.skip_rows)
        .with_skip_lines(options.skip_lines)
        .with_infer_schema_length(rows_read)
        .with_raise_if_empty(options.raise_if_empty)
        .with_parse_options(parse_options(options, &unnamed));
    let schema = lazy_reader(path, options, header)
        .finish()?
        .collect_schema()?;
    Ok((*schema).clone())
}

struct Renaming {
    file: Vec<PlSmallStr>,
    named: Schema,
}

impl Renaming {
    fn new(header: &Schema, new_columns: &[PlSmallStr]) -> PolarsResult<Self> {
        polars_ensure!(
            new_columns.len() <= header.len(),
            ComputeError: "{} new column names for a file of {} columns",
            new_columns.len(),
            header.len()
        );
        let file: Vec<PlSmallStr> = header.iter_names().cloned().collect();
        let names = new_columns
            .iter()
            .chain(file.iter().skip(new_columns.len()));
        let mut named = Schema::with_capacity(file.len());
        for (name, dtype) in names.zip(header.iter_values()) {
            polars_ensure!(
                named.insert(name.clone(), dtype.clone()).is_none(),
                Duplicate: "column with name '{}' has more than one occurrence",
                name
            );
        }
        Ok(Self { file, named })
    }

    fn file_name(&self, name: &str) -> PolarsResult<PlSmallStr> {
        Ok(self.file[self.named.try_index_of(name)?].clone())
    }

    fn new_name(&self, file_name: &str) -> PlSmallStr {
        match self.file.iter().position(|n| n == file_name) {
            Some(i) => self.named.get_at_index(i).unwrap().0.clone(),
            None => file_name.into(),
        }
    }

    fn changes(&self) -> (Vec<PlSmallStr>, Vec<PlSmallStr>) {
        self.file
            .iter()
            .zip(self.named.iter_names())
            .filter(|(file, named)| file != named)
            .map(|(file, named)| (file.clone(), named.clone()))
            .unzip()
    }

    fn in_file_names(&self, request: &CsvRequest) -> PolarsResult<CsvRequest> {
        require_override_columns(&self.named, request)?;
        require_free_row_index(&self.named, request)?;
        let overrides = match &request.overrides {
            None => None,
            Some(overrides) => {
                let fields = overrides
                    .iter()
                    .map(|(name, dtype)| {
                        Ok(Field::new(self.file_name(name)?, dtype.clone()))
                    })
                    .collect::<PolarsResult<Vec<_>>>()?;
                Some(Arc::new(Schema::from_iter(fields)))
            }
        };
        let null_values = match &request.null_values {
            Some(NullValues::Named(pairs)) => Some(NullValues::Named(
                pairs
                    .iter()
                    .map(|(name, marker)| {
                        Ok((self.file_name(name)?, marker.clone()))
                    })
                    .collect::<PolarsResult<Vec<_>>>()?,
            )),
            other => other.clone(),
        };
        let selection = match &request.selection {
            Selection::Names(names) => Selection::Names(
                names
                    .iter()
                    .map(|name| self.file_name(name))
                    .collect::<PolarsResult<Vec<_>>>()?,
            ),
            other => other.clone(),
        };
        Ok(CsvRequest {
            comment_prefix: request.comment_prefix.clone(),
            row_index: None,
            null_values,
            overrides,
            new_columns: Vec::new(),
            selection,
        })
    }
}

fn require_override_columns(
    header: &Schema,
    request: &CsvRequest,
) -> PolarsResult<()> {
    let Some(overrides) = &request.overrides else {
        return Ok(());
    };
    let missing: Vec<String> = overrides
        .iter_names()
        .filter(|name| !header.contains(name))
        .map(|name| format!("{:?}", name.as_str()))
        .collect();
    polars_ensure!(
        missing.is_empty(),
        ComputeError: "schema overrides name columns not in the file: {}",
        missing.join(", ")
    );
    Ok(())
}

fn require_free_row_index(
    header: &Schema,
    request: &CsvRequest,
) -> PolarsResult<()> {
    let Some(row_index) = &request.row_index else {
        return Ok(());
    };
    polars_ensure!(
        !header.contains(&row_index.name),
        Duplicate:
        "cannot add row_index with name '{}': column already exists in file.",
        row_index.name
    );
    Ok(())
}

fn select(lf: LazyFrame, request: &CsvRequest) -> PolarsResult<LazyFrame> {
    if matches!(request.selection, Selection::Every) {
        return Ok(lf);
    }
    let mut schema = (*lf.clone().collect_schema()?).clone();
    let index_name = request.row_index.as_ref().map(|ri| ri.name.clone());
    if let Some(name) = &index_name {
        schema.shift_remove(name);
    }
    let mut picked = match &request.selection {
        Selection::Every => unreachable!(),
        Selection::Names(names) => names
            .iter()
            .map(|name| schema.try_index_of(name))
            .collect::<PolarsResult<Vec<_>>>()?,
        Selection::Indices(indices) => indices.clone(),
    };
    picked.sort_unstable();
    if let Some(&last) = picked.last() {
        polars_ensure!(
            last < schema.len(),
            OutOfBounds: "projection index: {} is out of bounds for csv schema with length: {}",
            last,
            schema.len()
        );
    }
    let columns = index_name.into_iter().chain(
        picked
            .into_iter()
            .map(|i| schema.get_at_index(i).unwrap().0.clone()),
    );
    Ok(lf.select(columns.map(col).collect::<Vec<_>>()))
}

fn reads_header_at_scan(request: &CsvRequest) -> bool {
    request.overrides.is_some() || !request.new_columns.is_empty()
}

fn renamed_scan(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<LazyFrame> {
    let renaming = Renaming::new(
        &header_names(path, options, request)?,
        &request.new_columns,
    )?;
    let plain = CsvRequest {
        selection: Selection::Every,
        ..renaming.in_file_names(request)?
    };
    let (from, to) = renaming.changes();
    let lf = lazy_reader(path, options, read_options(options, &plain))
        .finish()?
        .rename(from, to, true);
    Ok(match &request.row_index {
        Some(ri) => lf.with_row_index(ri.name.clone(), Some(ri.offset)),
        None => lf,
    })
}

fn csv_scan(
    path: &str,
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<LazyFrame> {
    let request = decode(options, arrays)?;
    if reads_header_at_scan(&request) {
        require_path(
            path,
            &PathRules {
                glob: options.glob,
                directory: true,
            },
        )?;
    }
    let lf = if request.new_columns.is_empty() {
        let lf = lazy_reader(path, options, read_options(options, &request))
            .finish()?;
        if request.overrides.is_some() {
            require_override_columns(
                &header_names(path, options, &request)?,
                &request,
            )?;
        }
        lf
    } else {
        renamed_scan(path, options, &request)?
    };
    select(lf, &request)
}

fn eager_plain(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<DataFrame> {
    let read = read_options(options, request);
    let read = match &request.selection {
        Selection::Every => read,
        Selection::Names(names) => {
            read.with_columns(Some(names.clone().into_boxed_slice().into()))
        }
        Selection::Indices(indices) => {
            read.with_projection(Some(Arc::new(indices.clone())))
        }
    };
    read.try_into_reader_with_file_path(Some(path.into()))?
        .finish()
}

fn eager_renamed(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<DataFrame> {
    let renaming = Renaming::new(
        &header_names(path, options, request)?,
        &request.new_columns,
    )?;
    let mut df = eager_plain(path, options, &renaming.in_file_names(request)?)?;
    let names: Vec<PlSmallStr> = df
        .get_column_names()
        .into_iter()
        .map(|name| renaming.new_name(name))
        .collect();
    df.set_column_names(&names)?;
    match &request.row_index {
        Some(ri) => df.with_row_index(ri.name.clone(), Some(ri.offset)),
        None => Ok(df),
    }
}

fn eager_read(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<DataFrame> {
    if !request.new_columns.is_empty() {
        return eager_renamed(path, options, request);
    }
    if request.overrides.is_some() || request.row_index.is_some() {
        let header = header_names(path, options, request)?;
        require_override_columns(&header, request)?;
        require_free_row_index(&header, request)?;
    }
    eager_plain(path, options, request)
}

fn csv_read(
    path: &str,
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<DataFrame> {
    if is_pattern(path, options.glob) {
        return csv_scan(path, options, arrays)?.collect();
    }
    eager_read(path, options, &decode(options, arrays)?)
}

macro_rules! csv_entry {
    ($name:ident -> $out:ty, |$path:ident, $options:ident, $arrays:ident| $body:expr) => {
        #[no_mangle]
        #[allow(clippy::too_many_arguments)]
        pub extern "C" fn $name(
            $path: *const c_char,
            $options: CompatCsvOptions,
            comment_prefix: *const c_char,
            row_index_name: *const c_char,
            null_values: *const *const c_char,
            null_values_len: usize,
            null_columns: *const *const c_char,
            null_markers: *const *const c_char,
            named_nulls_len: usize,
            override_names: *const *const c_char,
            override_dtypes: *const CompatDType,
            overrides_len: usize,
            new_columns: *const *const c_char,
            new_columns_len: usize,
            columns: *const *const c_char,
            columns_len: usize,
            projection: *const usize,
            projection_len: usize,
        ) -> *mut $out {
            let $arrays = CsvArrays {
                comment_prefix,
                row_index_name,
                null_values,
                null_values_len,
                null_columns,
                null_markers,
                named_nulls_len,
                override_names,
                override_dtypes,
                overrides_len,
                new_columns,
                new_columns_len,
                columns,
                columns_len,
                projection,
                projection_len,
            };
            $body
        }
    };
}

csv_entry!(lazyframe_scan_csv_v2 -> LazyFrame, |path, options, arrays| {
    scan(path, |path| csv_scan(path, &options, &arrays))
});

csv_entry!(dataframe_read_csv_v2 -> DataFrame, |path, options, arrays| {
    read_path(
        path,
        PathRules {
            glob: options.glob,
            directory: false,
        },
        |path| csv_read(path, &options, &arrays),
    )
});
