use super::test_util::*;
use super::*;

type Work = fn() -> PolarsResult<i32>;

type Helper = fn(Work) -> Option<i32>;

const HELPERS: &[(&str, Helper)] = &[
    ("boxed_result", |f| take_box(boxed_result(f))),
    ("scalar_result", |f| {
        Some(scalar_result(-1, f)).filter(|&v| v != -1)
    }),
    ("boxed_unguarded", |f| take_box(boxed_unguarded(f))),
];

const GUARDING: [&str; 2] = ["boxed_result", "scalar_result"];

#[test]
fn every_helper_records_an_error_and_fails() {
    for &(name, helper) in HELPERS {
        clear_last_error();
        assert_eq!(
            helper(|| Err(polars_err!(ComputeError: "no luck"))),
            None,
            "{}",
            name
        );
        assert_eq!(recorded_error().as_deref(), Some("no luck"), "{}", name);
    }
}

#[test]
fn every_helper_clears_a_stale_reason_on_success() {
    for &(name, helper) in HELPERS {
        set_last_error("stale");
        assert_eq!(helper(|| Ok(7)), Some(7), "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
    }
}

#[test]
fn every_guarding_helper_records_a_panic_and_fails() {
    for &(name, helper) in HELPERS {
        if !GUARDING.contains(&name) {
            continue;
        }
        clear_last_error();
        assert_eq!(helper(|| panic!("boom")), None, "{}", name);
        assert_eq!(
            recorded_error().as_deref(),
            Some("polars panicked: boom"),
            "{}",
            name
        );
    }
}
