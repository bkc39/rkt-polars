/// The Parquet reader and scan options; field order mirrors
/// `_CompatParquetReadOptions` in `polars/private/parquet.rkt`.
/// `parallel` is 0 auto, 1 columns, 2 row groups, 3 prefiltered, 4 none.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatParquetReadOptions {
    pub has_n_rows: bool,
    pub parallel: u8,
    pub use_statistics: bool,
    pub low_memory: bool,
    pub rechunk: bool,
    pub cache: bool,
    pub glob: bool,
    pub allow_missing_columns: bool,
    pub row_index_offset: u32,
    pub n_rows: usize,
}

impl Default for CompatParquetReadOptions {
    fn default() -> Self {
        Self {
            has_n_rows: false,
            parallel: 0,
            use_statistics: true,
            low_memory: false,
            rechunk: false,
            cache: true,
            glob: true,
            allow_missing_columns: false,
            row_index_offset: 0,
            n_rows: 0,
        }
    }
}

/// The Parquet writer options; field order mirrors
/// `_CompatParquetWriteOptions` in `polars/private/parquet.rkt`.
/// `compression` is 0 uncompressed, 1 snappy, 2 gzip, 3 brotli, 4 lz4,
/// 5 zstd; `statistics` sets bit 0 for min, 1 max, 2 distinct count and
/// 3 null count.
#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatParquetWriteOptions {
    pub compression: u8,
    pub has_compression_level: bool,
    pub statistics: u8,
    pub has_row_group_size: bool,
    pub has_data_page_size: bool,
    pub compression_level: i32,
    pub row_group_size: usize,
    pub data_page_size: usize,
}

impl Default for CompatParquetWriteOptions {
    fn default() -> Self {
        Self {
            compression: 5,
            has_compression_level: false,
            statistics: 0b1011,
            has_row_group_size: false,
            has_data_page_size: false,
            compression_level: 0,
            row_group_size: 0,
            data_page_size: 0,
        }
    }
}
