/// The scalar CSV reader options; field order mirrors `_CompatCsvOptions` in
/// `polars/private/csv.rkt`.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatCsvOptions {
    pub has_header: u8,
    pub separator: u8,
    pub has_quote_char: u8,
    pub quote_char: u8,
    pub ignore_errors: u8,
    pub try_parse_dates: u8,
    pub lossy_utf8: u8,
    pub has_n_rows: u8,
    pub has_infer_schema_length: u8,
    pub glob: u8,
    pub skip_rows: usize,
    pub n_rows: usize,
    pub infer_schema_length: usize,
}

impl Default for CompatCsvOptions {
    fn default() -> Self {
        Self {
            has_header: 1,
            separator: b',',
            has_quote_char: 1,
            quote_char: b'"',
            ignore_errors: 0,
            try_parse_dates: 0,
            lossy_utf8: 0,
            has_n_rows: 0,
            has_infer_schema_length: 1,
            glob: 1,
            skip_rows: 0,
            n_rows: 0,
            infer_schema_length: 100,
        }
    }
}
