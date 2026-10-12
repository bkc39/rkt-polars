/// The scalar CSV reader options; field order mirrors `_CompatCsvOptions` in
/// `polars/private/csv.rkt`.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatCsvOptions {
    pub has_header: bool,
    pub separator: u8,
    pub has_quote_char: bool,
    pub quote_char: u8,
    pub eol_char: u8,
    pub ignore_errors: bool,
    pub try_parse_dates: bool,
    pub lossy_utf8: bool,
    pub has_n_rows: bool,
    pub has_infer_schema_length: bool,
    pub glob: bool,
    pub truncate_ragged_lines: bool,
    pub decimal_comma: bool,
    pub raise_if_empty: bool,
    pub missing_utf8_is_empty_string: bool,
    pub row_index_offset: u32,
    pub skip_rows: usize,
    pub skip_lines: usize,
    pub skip_rows_after_header: usize,
    pub n_rows: usize,
    pub infer_schema_length: usize,
}

impl Default for CompatCsvOptions {
    fn default() -> Self {
        Self {
            has_header: true,
            separator: b',',
            has_quote_char: true,
            quote_char: b'"',
            eol_char: b'\n',
            ignore_errors: false,
            try_parse_dates: false,
            lossy_utf8: false,
            has_n_rows: false,
            has_infer_schema_length: true,
            glob: true,
            truncate_ragged_lines: false,
            decimal_comma: false,
            raise_if_empty: true,
            missing_utf8_is_empty_string: false,
            row_index_offset: 0,
            skip_rows: 0,
            skip_lines: 0,
            skip_rows_after_header: 0,
            n_rows: 0,
            infer_schema_length: 100,
        }
    }
}

/// The scalar CSV writer options; field order mirrors `_CompatCsvWriteOptions`
/// in `polars/private/csv.rkt`. `quote_style` is 0 necessary, 1 always,
/// 2 non-numeric, 3 never.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatCsvWriteOptions {
    pub include_header: bool,
    pub include_bom: bool,
    pub separator: u8,
    pub quote_char: u8,
    pub quote_style: u8,
    pub decimal_comma: bool,
    pub has_float_scientific: bool,
    pub float_scientific: bool,
    pub has_float_precision: bool,
    pub float_precision: usize,
    pub batch_size: usize,
}

impl Default for CompatCsvWriteOptions {
    fn default() -> Self {
        Self {
            include_header: true,
            include_bom: false,
            separator: b',',
            quote_char: b'"',
            quote_style: 0,
            decimal_comma: false,
            has_float_scientific: false,
            float_scientific: false,
            has_float_precision: false,
            float_precision: 0,
            batch_size: 1024,
        }
    }
}
