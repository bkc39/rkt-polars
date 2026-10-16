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

#[test]
fn guard_panic_records_the_panic_as_the_reason() {
    clear_last_error();
    assert_eq!(guard_panic(|| -> Option<()> { panic!("boom") }), None);
    assert_eq!(recorded_error().as_deref(), Some("polars panicked: boom"));
    assert_eq!(guard_panic(|| -> Option<()> { panic!("boom {}", 2) }), None);
    assert_eq!(recorded_error().as_deref(), Some("polars panicked: boom 2"));
    assert_eq!(guard_panic(|| Some(7)), Some(7));
}

#[test]
fn a_panic_is_quiet_on_a_guarded_thread() {
    assert!(panic_is_quiet(1, 1, || false));
    assert!(panic_is_quiet(2, 3, || false));
}

#[test]
fn a_panic_is_quiet_on_a_polars_worker_while_a_guard_runs() {
    assert!(panic_is_quiet(0, 1, || true));
}

#[test]
fn a_panic_on_an_unrelated_thread_is_reported_while_a_guard_runs() {
    assert!(!panic_is_quiet(0, 1, || false));
}

#[test]
fn a_panic_is_reported_when_no_guard_runs() {
    assert!(!panic_is_quiet(0, 0, || panic!("not consulted")));
}

#[test]
fn a_polars_pool_thread_is_a_polars_worker() {
    assert!(!on_polars_worker());
    assert!(polars_core::runtime::THREAD_POOL.install(on_polars_worker));
}

const HOOK_CHILD: &str = "RKT_POLARS_HOOK_CHILD";

fn panic_on_a_thread(message: &'static str) {
    assert!(std::thread::spawn(move || panic!("{}", message))
        .join()
        .is_err());
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<String>()
        .cloned()
        .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
        .unwrap_or_default()
}

#[test]
#[ignore = "run by the_quiet_hook_reports_every_panic_it_does_not_catch"]
fn hook_child() {
    if std::env::var_os(HOOK_CHILD).is_none() {
        return;
    }
    let reported = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink = reported.clone();
    std::panic::set_hook(Box::new(move |info| {
        sink.lock().unwrap().push(panic_message(info.payload()));
    }));
    assert_eq!(guard_panic(|| -> Option<()> { panic!("guarded") }), None);
    assert_eq!(
        guard_panic(|| {
            panic_on_a_thread("unrelated");
            Some(())
        }),
        Some(())
    );
    assert_eq!(
        guard_panic(|| -> Option<()> {
            polars_core::runtime::THREAD_POOL.install(|| panic!("pool"))
        }),
        None
    );
    panic_on_a_thread("outside");
    let reported = reported.lock().unwrap().clone();
    assert_eq!(reported, ["unrelated", "outside"]);
}

#[test]
fn the_quiet_hook_reports_every_panic_it_does_not_catch() {
    let mut child =
        std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::last_error::hook_child", "--ignored"])
            .env(HOOK_CHILD, "1")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
    let deadline =
        std::time::Instant::now() + std::time::Duration::from_secs(60);
    let finished = loop {
        if child.try_wait().unwrap().is_some() {
            break true;
        }
        if std::time::Instant::now() > deadline {
            child.kill().unwrap();
            break false;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    let output = child.wait_with_output().unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        finished && output.status.success() && stdout.contains("1 passed"),
        "{:?}\n{}\n{}",
        output.status,
        stdout,
        String::from_utf8_lossy(&output.stderr)
    );
}
