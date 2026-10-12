/// The scalar NDJSON reader options; field order mirrors
/// `_CompatNdjsonOptions` in `polars/private/json.rkt`.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatNdjsonOptions {
    pub has_schema: bool,
    pub has_infer_schema_length: bool,
    pub has_batch_size: bool,
    pub has_n_rows: bool,
    pub low_memory: bool,
    pub rechunk: bool,
    pub ignore_errors: bool,
    pub infer_schema_length: usize,
    pub batch_size: usize,
    pub n_rows: usize,
    pub row_index_offset: usize,
    pub schema_len: usize,
    pub overrides_len: usize,
}

impl Default for CompatNdjsonOptions {
    fn default() -> Self {
        Self {
            has_schema: false,
            has_infer_schema_length: true,
            has_batch_size: true,
            has_n_rows: false,
            low_memory: false,
            rechunk: false,
            ignore_errors: false,
            infer_schema_length: 100,
            batch_size: 1024,
            n_rows: 0,
            row_index_offset: 0,
            schema_len: 0,
            overrides_len: 0,
        }
    }
}
