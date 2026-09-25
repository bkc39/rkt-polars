use super::test_util::*;
use super::*;

#[test]
fn record_keeps_the_cause_alone() {
    clear_last_error();
    assert!(record(Err::<(), _>("boom")).is_none());
    assert_eq!(recorded_error().as_deref(), Some("boom"));
}

#[test]
fn record_leaves_success_untouched() {
    clear_last_error();
    assert_eq!(record(Ok::<_, String>(7)), Some(7));
    assert_eq!(recorded_error(), None);
}

#[test]
fn decode_path_names_the_defect() {
    assert!(decode_path(ptr::null()).is_none());
    assert_eq!(recorded_error().as_deref(), Some("path is null"));

    let invalid = [0xffu8, 0];
    assert!(decode_path(invalid.as_ptr() as *const c_char).is_none());
    let msg = recorded_error().expect("a reason");
    assert!(msg.starts_with("path is not valid UTF-8"), "{:?}", msg);
}

#[test]
fn reading_the_reason_leaves_it_in_place() {
    set_last_error("kept");
    assert_eq!(recorded_error().as_deref(), Some("kept"));
    assert_eq!(recorded_error().as_deref(), Some("kept"));
}
