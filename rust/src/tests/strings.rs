use super::test_util::*;
use super::*;

fn nul_names() -> Vec<&'static str> {
    vec!["\0", "a\0b", "a\0", "\0a", "\0\0", "東京\0😀", "a\0\0b"]
}

fn lists() -> Vec<Vec<String>> {
    let owned = |xs: &[&str]| xs.iter().map(|x| x.to_string()).collect();
    vec![
        vec![],
        owned(&[""]),
        owned(&nul_names()),
        owned(&["é", "東京 😀", "", "abcdefgh", "abcdefghi"]),
        (0..300)
            .map(|i| format!("column {} é 東京 😀", i))
            .collect(),
    ]
}

fn read_single(block: &[u64]) -> Result<Option<String>, StrError> {
    unsafe { str_arg(block.as_ptr()) }.map(|s| s.map(str::to_owned))
}

fn read_list(block: &[u64]) -> Result<Vec<String>, StrError> {
    unsafe { str_list_arg(block.as_ptr()) }
        .map(|xs| xs.into_iter().map(str::to_owned).collect())
}

fn words(bytes: &[u8]) -> Vec<u64> {
    bytes
        .chunks(8)
        .map(|chunk| {
            let mut word = [0u8; 8];
            word[..chunk.len()].copy_from_slice(chunk);
            u64::from_ne_bytes(word)
        })
        .collect()
}

fn single_block(len: u64, bytes: &[u8]) -> Vec<u64> {
    let data = words(bytes);
    let mut block = vec![(2 + data.len()) as u64, len];
    block.extend(data);
    block
}

fn list_block(offsets: &[u64], bytes: &[u8]) -> Vec<u64> {
    let data = words(bytes);
    let mut block = vec![
        (2 + offsets.len() + data.len()) as u64,
        (offsets.len() - 1) as u64,
    ];
    block.extend_from_slice(offsets);
    block.extend(data);
    block
}

#[test]
fn a_result_block_reads_back_as_its_strings() {
    for xs in lists() {
        assert_eq!(take_strs(str_list_out(&xs)), xs);
        for x in &xs {
            assert_eq!(&take_str(str_out(x)), x);
        }
    }
}

#[test]
fn a_block_is_read_through_its_own_layout() {
    assert_eq!(
        read_single(&single_block(3, b"a\0b")),
        Ok(Some("a\0b".into()))
    );
    assert_eq!(read_single(&single_block(0, b"")), Ok(Some(String::new())));
    assert_eq!(
        read_list(&list_block(&[0, 1, 1, 4], b"a\0bc")),
        Ok(vec!["a".into(), "".into(), "\0bc".into()])
    );
    assert_eq!(read_list(&list_block(&[0], b"")), Ok(vec![]));
}

#[test]
fn null_is_absent_or_empty() {
    assert_eq!(unsafe { str_arg(ptr::null()) }, Ok(None));
    assert_eq!(unsafe { str_list_arg(ptr::null()) }, Ok(vec![]));
}

#[test]
fn a_malformed_block_names_its_defect() {
    let singles: [(Vec<u64>, StrError); 4] = [
        (vec![1, 0], StrError::Truncated),
        (vec![2, 1], StrError::Truncated),
        (vec![3, 9, 0], StrError::Truncated),
        (single_block(1, &[0xff]), StrError::NotUtf8),
    ];
    for (block, defect) in singles {
        assert_eq!(read_single(&block), Err(defect), "{:?}", block);
    }
    let lists: [(Vec<u64>, StrError); 7] = [
        (vec![0, 0], StrError::Truncated),
        (vec![3, 1, 0], StrError::Truncated),
        (vec![3, u64::MAX, 0], StrError::Truncated),
        (list_block(&[1, 2], b"ab"), StrError::FirstOffset),
        (list_block(&[0, 2, 1], b"ab"), StrError::OutOfOrder),
        (list_block(&[0, 9], b"ab"), StrError::PastEnd),
        (list_block(&[0, 1, 2], "é".as_bytes()), StrError::NotUtf8),
    ];
    for (block, defect) in lists {
        assert_eq!(read_list(&block), Err(defect), "{:?}", block);
    }
    assert_eq!(
        read_list(&list_block(&[0, 1], &[0xc3])),
        Err(StrError::NotUtf8)
    );
}

#[test]
fn a_defect_displays_its_cause_alone() {
    assert_eq!(
        StrError::Truncated.to_string(),
        "a string block is shorter than its header says"
    );
    assert_eq!(
        StrError::FirstOffset.to_string(),
        "a string block's first offset is not 0"
    );
    assert_eq!(
        StrError::OutOfOrder.to_string(),
        "string offsets are out of order"
    );
    assert_eq!(
        StrError::PastEnd.to_string(),
        "a string offset is past the block's bytes"
    );
    assert_eq!(StrError::NotUtf8.to_string(), "a string is not valid UTF-8");
}

/// Other tests drop blocks concurrently, so some attempt must see exactly
/// `releases` new drops.
fn counts_exactly(releases: usize, drop: impl Fn()) -> bool {
    (0..1000).any(|_| {
        let before = str_block_drop_count();
        drop();
        str_block_drop_count() - before == releases
    })
}

#[test]
fn a_block_drop_counts_one_release_and_a_null_drop_none() {
    assert!(counts_exactly(1, || str_block_drop(str_out("a\0b"))));
    let list = || str_list_out(["a", "b"]);
    assert!(counts_exactly(1, || str_block_drop(list())));
    assert!(counts_exactly(0, || str_block_drop(ptr::null_mut())));
}

#[test]
fn results_keep_a_nul() {
    let s = make_i32("x", &[1]);
    let df = make_df(&[s]);
    let lf = dataframe_lazy(df);
    let renamed = Box::into_raw(Box::new(
        unsafe { (*lf).clone() }.select([col("x").alias("a\0b")]),
    ));
    let plan = take_str(lazyframe_explain_v2(renamed, false, false));
    assert!(plan.contains("a\0b"), "{:?}", plan);
    let frame = lazyframe_collect(renamed);
    assert_eq!(read_column_names(frame), ["a\0b"]);
    assert_eq!(take_str(dataframe_column_name_v2(frame, 0)), "a\0b");
    assert!(dataframe_column_name_v2(frame, 1).is_null());
    assert!(take_str(dataframe_to_string_v2(frame)).contains("a\0b"));
    let column =
        unsafe { (*frame).column("a\0b").unwrap().as_materialized_series() }
            .clone();
    let named = Box::into_raw(Box::new(column));
    assert_eq!(take_str(series_name_v2(named)), "a\0b");
    let e = Box::into_raw(Box::new(col("a\0b").alias("c\0d")));
    assert_eq!(take_str(expr_meta_output_name_v2(e)), "c\0d");
    assert_eq!(take_strs(expr_meta_root_names(e)), ["a\0b"]);
    assert!(take_str(expr_to_string_v2(e)).contains("c\0d"));
    set_last_error("cause a\0b");
    assert_eq!(recorded_error().as_deref(), Some("cause a\0b"));
    expr_drop(e);
    series_drop(named);
    dataframe_drop(frame);
    lazyframe_drop(renamed);
    lazyframe_drop(lf);
    dataframe_drop(df);
    series_drop(s);
}
