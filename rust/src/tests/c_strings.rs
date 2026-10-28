use super::guard_audit::{fixture, tree, walk};
use proc_macro2::Ident;
use syn::visit::{self, Visit};
use syn::ReturnType;

#[derive(Default)]
struct CChar(bool);

impl<'ast> Visit<'ast> for CChar {
    fn visit_ident(&mut self, ident: &'ast Ident) {
        self.0 |= ident == "c_char";
        visit::visit_ident(self, ident);
    }
}

fn returns_c_char(output: &ReturnType) -> bool {
    let mut found = CChar::default();
    found.visit_return_type(output);
    found.0
}

fn c_string_results(files: &[String]) -> Vec<String> {
    let krate = walk(files);
    let mut problems = krate.problems;
    problems.extend(
        krate
            .functions
            .iter()
            .filter(|f| f.entry && returns_c_char(&f.output))
            .map(|f| {
                format!("{} returns a C string: return a StrOut block", f.name)
            }),
    );
    problems
}

#[test]
fn no_entry_point_returns_a_c_string() {
    let problems = c_string_results(&tree());
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_result_rule_refuses_a_planted_c_string() {
    let planted = fixture(
        r#"
#[no_mangle]
pub extern "C" fn planted_const() -> *const c_char { ptr::null() }

#[no_mangle]
pub extern "C" fn planted_mut() -> *mut std::os::raw::c_char { ptr::null_mut() }

macro_rules! export_c_string {
    ($name:ident) => {
        #[no_mangle]
        pub extern "C" fn $name() -> *const c_char { ptr::null() }
    };
}
export_c_string!(planted_by_macro);

#[no_mangle]
pub extern "C" fn block() -> StrOut { ptr::null_mut() }

#[no_mangle]
pub extern "C" fn takes_a_path(path: *const c_char) -> i32 { 0 }

fn internal() -> *const c_char { ptr::null() }
"#,
    );
    assert_eq!(
        c_string_results(&planted),
        [
            "planted_const returns a C string: return a StrOut block",
            "planted_mut returns a C string: return a StrOut block",
            "planted_by_macro returns a C string: return a StrOut block",
        ]
    );
}
