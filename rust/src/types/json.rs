/// The scalar JSON reader options; field order mirrors `_CompatJsonOptions` in
/// `polars/private/json.rkt`.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatJsonOptions {
    pub has_schema: bool,
    pub has_infer_schema_length: bool,
    pub infer_schema_length: usize,
    pub schema_len: usize,
    pub overrides_len: usize,
}

impl Default for CompatJsonOptions {
    fn default() -> Self {
        Self {
            has_schema: false,
            has_infer_schema_length: true,
            infer_schema_length: 100,
            schema_len: 0,
            overrides_len: 0,
        }
    }
}
