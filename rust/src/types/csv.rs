/// The scalar CSV reader options; field order mirrors `_CompatCsvOptions` in
/// `polars/private/csv.rkt`.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatCsvOptions {
    pub has_header: bool,
    pub separator: u8,
    pub has_quote_char: bool,
    pub quote_char: u8,
    pub ignore_errors: bool,
    pub try_parse_dates: bool,
    pub lossy_utf8: bool,
    pub has_n_rows: bool,
    pub has_infer_schema_length: bool,
    pub glob: bool,
    pub skip_rows: usize,
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
            ignore_errors: false,
            try_parse_dates: false,
            lossy_utf8: false,
            has_n_rows: false,
            has_infer_schema_length: true,
            glob: true,
            skip_rows: 0,
            n_rows: 0,
            infer_schema_length: 100,
        }
    }
}
