use super::test_util::*;
use super::*;
use polars::io::parquet::read::ParallelStrategy;
use polars_parquet_format::thrift::protocol::TCompactInputProtocol;
use polars_parquet_format::{ColumnIndex, OffsetIndex};

fn frame(rows: i64) -> *mut DataFrame {
    let a = Series::new("a".into(), (0..rows).collect::<Vec<_>>());
    let b = Series::new(
        "b".into(),
        (0..rows).map(|i| format!("s{}", i % 7)).collect::<Vec<_>>(),
    );
    Box::into_raw(Box::new(
        DataFrame::new(rows as usize, vec![a.into(), b.into()]).unwrap(),
    ))
}

fn write_with(
    df: *mut DataFrame,
    path: &std::path::Path,
    options: CompatParquetWriteOptions,
) -> i32 {
    let p = cstr(path.to_str().unwrap());
    dataframe_write_parquet_with_options(df, p.as_ptr(), options)
}

fn read_with(
    path: &std::path::Path,
    options: CompatParquetReadOptions,
) -> *mut DataFrame {
    let p = cstr(path.to_str().unwrap());
    dataframe_read_parquet_with_options_v2(
        p.as_ptr(),
        options,
        ptr::null(),
        ptr::null(),
        0,
        ptr::null(),
        ptr::null(),
        0,
    )
}

fn read_names(path: &std::path::Path, names: &[&str]) -> *mut DataFrame {
    let p = cstr(path.to_str().unwrap());
    let block = str_list_block(names);
    dataframe_read_parquet_with_options_v2(
        p.as_ptr(),
        CompatParquetReadOptions::default(),
        ptr::null(),
        ptr::null(),
        1,
        block.as_ptr(),
        ptr::null(),
        names.len(),
    )
}

fn read_indices(
    path: &std::path::Path,
    row_index: Option<&str>,
    indices: &[i64],
) -> *mut DataFrame {
    let p = cstr(path.to_str().unwrap());
    let name = row_index.map(str_block);
    dataframe_read_parquet_with_options_v2(
        p.as_ptr(),
        CompatParquetReadOptions::default(),
        name.as_ref().map_or(ptr::null(), |n| n.as_ptr()),
        ptr::null(),
        2,
        ptr::null(),
        indices.as_ptr(),
        indices.len(),
    )
}

fn metadata(path: &std::path::Path) -> FileMetadataRef {
    let file = std::fs::File::open(path).unwrap();
    ParquetReader::new(file).get_metadata().unwrap().clone()
}

fn codecs(path: &std::path::Path) -> Vec<String> {
    metadata(path).row_groups[0]
        .parquet_columns()
        .iter()
        .map(|column| format!("{:?}", column.compression()))
        .collect()
}

fn names_of(df: *mut DataFrame) -> Vec<String> {
    let df = unsafe { &*df };
    df.get_column_names()
        .into_iter()
        .map(|n| n.to_string())
        .collect()
}

#[test]
fn read_options_map_onto_the_scan_arguments() {
    let options = CompatParquetReadOptions {
        has_n_rows: true,
        n_rows: 7,
        parallel: 3,
        use_statistics: false,
        low_memory: true,
        rechunk: true,
        cache: false,
        glob: false,
        allow_missing_columns: true,
        row_index_offset: 9,
    };
    let names = ParquetNames {
        row_index_name: Some("i".into()),
        include_file_paths: Some("file".into()),
    };
    let args = parquet_scan_args(&options, names).unwrap();
    assert_eq!(args.n_rows, Some(7));
    assert_eq!(args.parallel, ParallelStrategy::Prefiltered);
    assert!(!args.use_statistics && args.low_memory && args.rechunk);
    assert!(!args.cache && !args.glob && args.allow_missing_columns);
    let row_index = args.row_index.unwrap();
    assert_eq!((row_index.name.as_str(), row_index.offset), ("i", 9));
    assert_eq!(args.include_file_paths.as_deref(), Some("file"));
    assert_eq!(args.hive_options.enabled, None);

    let defaults = parquet_scan_args(
        &CompatParquetReadOptions::default(),
        ParquetNames::default(),
    )
    .unwrap();
    assert_eq!(defaults.n_rows, None);
    assert_eq!(defaults.parallel, ParallelStrategy::Auto);
    assert!(defaults.use_statistics && defaults.cache && defaults.glob);
    assert!(
        defaults.row_index.is_none() && defaults.include_file_paths.is_none()
    );

    for (code, strategy) in [
        (0, ParallelStrategy::Auto),
        (1, ParallelStrategy::Columns),
        (2, ParallelStrategy::RowGroups),
        (3, ParallelStrategy::Prefiltered),
        (4, ParallelStrategy::None),
    ] {
        let options = CompatParquetReadOptions {
            parallel: code,
            ..Default::default()
        };
        let args =
            parquet_scan_args(&options, ParquetNames::default()).unwrap();
        assert_eq!(args.parallel, strategy);
    }
    let bad = CompatParquetReadOptions {
        parallel: 5,
        ..Default::default()
    };
    let err = parquet_scan_args(&bad, ParquetNames::default())
        .err()
        .unwrap();
    assert!(err.to_string().contains("unknown parallel strategy 5"));
}

#[test]
fn write_options_validate_the_compression_level() {
    let with =
        |compression: u8, level: Option<i32>| CompatParquetWriteOptions {
            compression,
            has_compression_level: level.is_some(),
            compression_level: level.unwrap_or(0),
            ..Default::default()
        };
    let level_error = |options: CompatParquetWriteOptions| {
        parquet_write_options(&options).err().unwrap().to_string()
    };
    for (compression, level, codec) in [
        (2, 10, "gzip"),
        (2, -1, "gzip"),
        (2, 300, "gzip"),
        (3, 12, "brotli"),
        (3, -1, "brotli"),
        (5, 0, "zstd"),
        (5, 23, "zstd"),
    ] {
        let message = level_error(with(compression, Some(level)));
        let expected = format!(
            "compression level {} is out of range for {}",
            level, codec
        );
        assert!(message.starts_with(&expected), "{:?}", message);
    }
    for (compression, level) in [
        (2, 0),
        (2, 9),
        (3, 0),
        (3, 11),
        (5, 1),
        (5, 22),
        (1, 99),
        (4, -5),
    ] {
        assert!(
            parquet_write_options(&with(compression, Some(level))).is_ok(),
            "{} {}",
            compression,
            level
        );
    }
    assert!(level_error(with(6, None)).contains("unknown compression 6"));

    let defaults =
        parquet_write_options(&CompatParquetWriteOptions::default()).unwrap();
    assert_eq!(defaults, ParquetWriteOptions::default());
    let zero_rows = CompatParquetWriteOptions {
        has_row_group_size: true,
        row_group_size: 0,
        has_data_page_size: true,
        data_page_size: 0,
        statistics: DISTINCT_COUNT,
        ..Default::default()
    };
    let options = parquet_write_options(&zero_rows).unwrap();
    assert_eq!(options.row_group_size, None);
    assert_eq!(options.data_page_size, Some(0));
    assert_eq!(
        options.statistics,
        StatisticsOptions {
            distinct_count: true,
            ..StatisticsOptions::empty()
        }
    );
}

#[test]
fn the_writer_applies_codec_row_groups_and_statistics() {
    let dir = scratch_dir();
    let df = frame(1000);
    for (code, codec) in [
        (0, "Uncompressed"),
        (1, "Snappy"),
        (2, "Gzip"),
        (3, "Brotli"),
        (4, "Lz4Raw"),
        (5, "Zstd"),
    ] {
        let path = dir.path().join(format!("{}.parquet", codec));
        let options = CompatParquetWriteOptions {
            compression: code,
            ..Default::default()
        };
        assert_eq!(write_with(df, &path, options), 0, "{}", codec);
        assert_eq!(codecs(&path), vec![codec.to_string(); 2]);
        let back = read_with(&path, CompatParquetReadOptions::default());
        assert!(unsafe { (*back).equals_missing(&*df) }, "{}", codec);
        dataframe_drop(back);
    }

    let path = dir.path().join("groups.parquet");
    let grouped = CompatParquetWriteOptions {
        has_row_group_size: true,
        row_group_size: 300,
        ..Default::default()
    };
    assert_eq!(write_with(df, &path, grouped), 0);
    let groups: Vec<usize> = metadata(&path)
        .row_groups
        .iter()
        .map(|group| group.num_rows())
        .collect();
    assert_eq!(groups, vec![300, 300, 300, 100]);

    let default_groups = CompatParquetWriteOptions {
        has_row_group_size: true,
        row_group_size: 0,
        ..Default::default()
    };
    assert_eq!(write_with(df, &path, default_groups), 0);
    assert_eq!(metadata(&path).row_groups.len(), 1);

    let size = |statistics: u8| {
        let path = dir.path().join(format!("stats-{}.parquet", statistics));
        let options = CompatParquetWriteOptions {
            statistics,
            ..Default::default()
        };
        assert_eq!(write_with(df, &path, options), 0);
        std::fs::metadata(&path).unwrap().len()
    };
    assert!(size(0) < size(NULL_COUNT));
    assert!(size(NULL_COUNT) < size(MIN | MAX | NULL_COUNT));
    dataframe_drop(df);
}

const MIN: u8 = 1;
const MAX: u8 = 2;
const DISTINCT_COUNT: u8 = 4;
const NULL_COUNT: u8 = 8;

const STATISTICS_SETS: [(&str, u8); 9] = [
    ("none", 0),
    ("min", MIN),
    ("max", MAX),
    ("min and max", MIN | MAX),
    ("null count", NULL_COUNT),
    ("max and null count", MAX | NULL_COUNT),
    ("distinct and null counts", DISTINCT_COUNT | NULL_COUNT),
    ("min, max and distinct count", MIN | MAX | DISTINCT_COUNT),
    ("all", MIN | MAX | DISTINCT_COUNT | NULL_COUNT),
];

const SPOTTY_ROWS: usize = 1000;

const SPOTTY_COLUMNS: [(&str, usize, bool); 3] =
    [("f", 10, false), ("n", 7, true), ("c", 9, true)];

fn spotty() -> *mut DataFrame {
    let f: Vec<Option<f64>> = (0..SPOTTY_ROWS)
        .map(|i| (i % 10 != 0).then_some(i as f64))
        .collect();
    let n: Vec<Option<i64>> = (0..SPOTTY_ROWS)
        .map(|i| (i % 7 != 0).then_some((i % 3 + 1) as i64))
        .collect();
    let c: Vec<Option<&str>> = (0..SPOTTY_ROWS)
        .map(|i| (i % 9 != 0).then_some(["x", "y", "z"][i % 3]))
        .collect();
    let c = Series::new("c".into(), &c)
        .cast(&DataType::from_categories(Categories::global()))
        .unwrap();
    Box::into_raw(Box::new(
        DataFrame::new(
            SPOTTY_ROWS,
            vec![
                Series::new("f".into(), &f).into(),
                Series::new("n".into(), &n).into(),
                c.into(),
            ],
        )
        .unwrap(),
    ))
}

#[test]
fn page_indexes_and_null_counts_follow_the_statistics_set() {
    let dir = scratch_dir();
    let df = spotty();
    for (name, statistics) in STATISTICS_SETS {
        let has = |bits: u8| statistics & bits == bits;
        let path = dir.path().join(format!("stats-{statistics}.parquet"));
        let options = CompatParquetWriteOptions {
            statistics,
            has_row_group_size: true,
            row_group_size: 300,
            has_data_page_size: true,
            data_page_size: 256,
            ..Default::default()
        };
        assert_eq!(write_with(df, &path, options), 0, "{name}");
        let back = read_with(&path, Default::default());
        assert!(unsafe { (*back).equals_missing(&*df) }, "{name}");
        dataframe_drop(back);

        let file = std::fs::read(&path).unwrap();
        let read = |offset: Option<i64>, length: Option<i32>| {
            let start = offset? as usize;
            let bytes = &file[start..start + length? as usize];
            Some(TCompactInputProtocol::new(bytes, usize::MAX))
        };
        let md = metadata(&path);
        let mut group_start = 0;
        for group in &md.row_groups {
            let rows = group.num_rows();
            let columns = group.parquet_columns().iter().zip(SPOTTY_COLUMNS);
            for (chunk, (column, period, dictionary)) in columns {
                let nulls = |from: usize, to: usize| {
                    (group_start + from..group_start + to)
                        .filter(|i| i % period == 0)
                        .count() as i64
                };
                let pages = read(
                    chunk.offset_index_offset(),
                    chunk.offset_index_length(),
                )
                .map(|mut p| OffsetIndex::read_from_in_protocol(&mut p))
                .unwrap()
                .unwrap()
                .page_locations;
                assert!(pages.len() >= 2, "{name} {column}");
                assert_eq!(
                    chunk.dictionary_page_offset().is_some(),
                    dictionary,
                    "{name} {column}"
                );
                let ends = pages
                    .iter()
                    .skip(1)
                    .map(|page| page.first_row_index as usize)
                    .chain([rows]);
                let page_nulls: Vec<i64> = pages
                    .iter()
                    .zip(ends)
                    .map(|(page, end)| {
                        nulls(page.first_row_index as usize, end)
                    })
                    .collect();
                assert_eq!(
                    chunk
                        .statistics(&md.footer_buf)
                        .and_then(|s| s.unwrap().null_count()),
                    has(NULL_COUNT).then_some(nulls(0, rows)),
                    "{name} {column}"
                );
                let index = read(
                    chunk.column_index_offset(),
                    chunk.column_index_length(),
                )
                .map(|mut p| {
                    ColumnIndex::read_from_in_protocol(&mut p).unwrap()
                });
                assert_eq!(index.is_some(), has(MIN | MAX), "{name} {column}");
                if let Some(index) = index {
                    assert_eq!(
                        index.null_pages,
                        vec![false; pages.len()],
                        "{name} {column}"
                    );
                    assert_eq!(
                        index.null_counts,
                        has(NULL_COUNT).then_some(page_nulls),
                        "{name} {column}"
                    );
                }
            }
            group_start += rows;
        }
    }
    dataframe_drop(df);
}

#[test]
fn an_invalid_level_fails_before_the_file_is_created() {
    let dir = scratch_dir();
    let path = dir.path().join("never.parquet");
    let df = frame(3);
    let options = CompatParquetWriteOptions {
        compression: 5,
        has_compression_level: true,
        compression_level: 30,
        ..Default::default()
    };
    assert_ne!(write_with(df, &path, options), 0);
    let reason = recorded_error().expect("a reason");
    assert!(
        reason.starts_with("compression level 30 is out of range for zstd"),
        "{:?}",
        reason
    );
    assert!(!path.exists());
    dataframe_drop(df);
}

#[test]
fn a_write_failing_once_staged_leaves_the_existing_file_as_it_was() {
    let dir = scratch_dir();
    let path = dir.path().join("keep.parquet");
    let df = frame(1000);
    let small = frame(3);
    let hollow = Box::into_raw(Box::new(
        DataFrame::new(
            3,
            vec![DataFrame::empty_with_height(3)
                .into_struct("s".into())
                .into_series()
                .into()],
        )
        .unwrap(),
    ));
    assert_eq!(write_with(df, &path, Default::default()), 0);
    let before = std::fs::read(&path).unwrap();

    assert_eq!(write_with(hollow, &path, Default::default()), 4);
    assert!(recorded_error().is_some());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    assert_eq!(entries(dir.path()), vec!["keep.parquet"]);

    let fresh = dir.path().join("fresh.parquet");
    assert_eq!(write_with(hollow, &fresh, Default::default()), 4);
    assert!(!fresh.exists());
    assert_eq!(entries(dir.path()), vec!["keep.parquet"]);

    assert_eq!(write_with(small, &path, Default::default()), 0);
    let back = read_with(&path, Default::default());
    assert!(unsafe { (*back).equals_missing(&*small) });
    assert_eq!(entries(dir.path()), vec!["keep.parquet"]);

    let sub = dir.path().join("sub");
    std::fs::create_dir(&sub).unwrap();
    assert_eq!(write_with(df, &sub, Default::default()), 3);
    let reason = recorded_error().expect("a reason");
    assert!(reason.starts_with("cannot create file: "), "{:?}", reason);
    assert_eq!(entries(dir.path()), vec!["keep.parquet", "sub"]);

    for p in [back, hollow, small, df] {
        dataframe_drop(p);
    }
}

#[test]
fn columns_select_by_name_or_position() {
    let dir = scratch_dir();
    let path = dir.path().join("cols.parquet");
    let df = frame(4);
    assert_eq!(write_with(df, &path, Default::default()), 0);

    let out = read_names(&path, &["b", "a"]);
    assert_eq!(names_of(out), vec!["b", "a"]);
    dataframe_drop(out);
    let out = read_indices(&path, None, &[-1]);
    assert_eq!(names_of(out), vec!["b"]);
    dataframe_drop(out);
    let out = read_indices(&path, Some("i"), &[0, 2]);
    assert_eq!(names_of(out), vec!["i", "b"]);
    dataframe_drop(out);
    let out = read_names(&path, &[]);
    assert_eq!(unsafe { (*out).shape() }, (0, 0));
    dataframe_drop(out);

    let refused = |out: *mut DataFrame, reason: &str| {
        assert!(out.is_null(), "{}", reason);
        assert_eq!(recorded_error().as_deref(), Some(reason));
    };
    refused(
        read_names(&path, &["a", "z"]),
        "columns not in the file: \"z\"",
    );
    refused(
        read_indices(&path, None, &[2]),
        "column index 2 is out of range for 2 columns",
    );
    refused(
        read_indices(&path, None, &[-3]),
        "column index -3 is out of range for 2 columns",
    );
    refused(
        read_indices(&path, None, &[1, -1]),
        "column \"b\" is selected more than once",
    );
    dataframe_drop(df);
}

#[test]
fn a_column_name_is_never_a_pattern() {
    let dir = scratch_dir();
    let path = dir.path().join("patterned.parquet");
    let columns: Vec<Column> = ["*", "^a.*$", "ab"]
        .iter()
        .map(|name| Series::new((*name).into(), &[1i64, 2]).into())
        .collect();
    let df = Box::into_raw(Box::new(DataFrame::new(2, columns).unwrap()));
    assert_eq!(write_with(df, &path, Default::default()), 0);
    for name in ["*", "^a.*$"] {
        let out = read_names(&path, &[name]);
        assert_eq!(names_of(out), vec![name]);
        dataframe_drop(out);
    }
    let out = read_indices(&path, None, &[0, 1]);
    assert_eq!(names_of(out), vec!["*", "^a.*$"]);
    dataframe_drop(out);
    dataframe_drop(df);
}

#[test]
fn new_entry_points_clear_a_stale_reason() {
    let dir = scratch_dir();
    let path = dir.path().join("fresh.parquet");
    let p = cstr(path.to_str().unwrap());
    let df = frame(3);

    set_last_error("stale");
    assert_eq!(write_with(df, &path, Default::default()), 0);
    assert_eq!(recorded_error(), None);

    set_last_error("stale");
    let out = read_with(&path, Default::default());
    assert!(!out.is_null());
    assert_eq!(recorded_error(), None);
    dataframe_drop(out);

    set_last_error("stale");
    let lf = lazyframe_scan_parquet_with_options_v2(
        p.as_ptr(),
        Default::default(),
        ptr::null(),
        ptr::null(),
    );
    assert!(!lf.is_null());
    assert_eq!(recorded_error(), None);

    set_last_error("stale");
    let plan = lazyframe_explain_v2(lf, true, false);
    assert!(take_str(plan).contains("Parquet SCAN"));
    assert_eq!(recorded_error(), None);

    assert!(lazyframe_explain_v2(ptr::null_mut(), true, false).is_null());
    assert_eq!(recorded_error().as_deref(), Some("lazyframe is null"));

    lazyframe_drop(lf);
    dataframe_drop(df);
}

#[test]
fn explain_reports_a_plan_that_cannot_resolve() {
    let df = frame(3);
    let lf = dataframe_lazy(df);
    let bad =
        Box::into_raw(Box::new(unsafe { (*lf).clone() }.select([col("nope")])));
    for (optimized, tree) in
        [(true, false), (false, false), (true, true), (false, true)]
    {
        assert!(lazyframe_explain_v2(bad, optimized, tree).is_null());
        let message = recorded_error().expect("a reason");
        assert!(
            message.contains("unable to find column \"nope\""),
            "{}",
            message
        );
        assert!(
            !message.contains("Resolved plan")
                && !message.contains("FAILED HERE"),
            "{}",
            message
        );
    }
    let plain = take_str(lazyframe_explain_v2(lf, false, false));
    let tree = take_str(lazyframe_explain_v2(lf, false, true));
    assert_ne!(plain, tree);
    lazyframe_drop(bad);
    lazyframe_drop(lf);
    dataframe_drop(df);
}

#[test]
fn a_row_index_past_the_index_type_names_the_overflow() {
    let dir = scratch_dir();
    let path = dir.path().join("index.parquet");
    let df = frame(4);
    assert_eq!(write_with(df, &path, Default::default()), 0);
    let name = str_block("i");
    let p = cstr(path.to_str().unwrap());
    let out = dataframe_read_parquet_with_options_v2(
        p.as_ptr(),
        CompatParquetReadOptions {
            row_index_offset: u32::MAX,
            ..Default::default()
        },
        name.as_ptr(),
        ptr::null(),
        0,
        ptr::null(),
        ptr::null(),
        0,
    );
    assert!(out.is_null());
    let reason = recorded_error().expect("a reason");
    assert!(
        reason.contains("row index from offset 4294967295 overflows u32"),
        "{}",
        reason
    );
    dataframe_drop(df);
}
