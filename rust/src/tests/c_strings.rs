use super::guard_audit::{fixture, tree, walk, Function};
use proc_macro2::Ident;
use std::path::Path;
use syn::visit::{self, Visit};
use syn::{FnArg, Pat, ReturnType};

const C_STRING_NAMES: &[&str] = &["path", "tz", "ambiguous", "non_existent"];

const C_STRING_PARAMETERS: &[&str] = &["string_drop"];

const C_STRING_READERS: &[&str] = &[
    "ffi/errors.rs",
    "ffi/slices.rs",
    "series/time_zone.rs",
    "series/constructors/",
];

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

fn c_char_parameters(f: &Function) -> Vec<String> {
    f.inputs
        .iter()
        .filter_map(|input| match input {
            FnArg::Typed(typed) => {
                let mut found = CChar::default();
                found.visit_type(&typed.ty);
                found.0.then(|| match typed.pat.as_ref() {
                    Pat::Ident(ident) => ident.ident.to_string(),
                    _ => "_".to_string(),
                })
            }
            FnArg::Receiver(_) => None,
        })
        .collect()
}

fn may_take_a_c_string(function: &str, parameter: &str) -> bool {
    C_STRING_NAMES.contains(&parameter)
        || (parameter == "name" && function.starts_with("series_new_"))
}

fn c_string_parameters(files: &[String], exempt: &[&str]) -> Vec<String> {
    let krate = walk(files);
    let mut problems = krate.problems;
    let entries: Vec<&Function> =
        krate.functions.iter().filter(|f| f.entry).collect();
    for f in &entries {
        if exempt.contains(&f.name.as_str()) {
            continue;
        }
        for parameter in c_char_parameters(f) {
            if !may_take_a_c_string(&f.name, &parameter) {
                problems.push(format!(
                    "{} takes {} as a C string: take a StrArg or StrListArg block",
                    f.name, parameter
                ));
            }
        }
    }
    for name in exempt {
        let takes = entries
            .iter()
            .any(|f| f.name == *name && !c_char_parameters(f).is_empty());
        if !takes {
            problems.push(format!(
                "{} is exempt but takes no C string: remove its exemption",
                name
            ));
        }
    }
    problems
}

fn sources_by_path(dir: &Path, root: &Path, out: &mut Vec<(String, String)>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .expect("readable source directory")
        .map(|e| e.expect("directory entry").path())
        .collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            if path.file_name() != Some("tests".as_ref()) {
                sources_by_path(&path, root, out);
            }
        } else if path.extension() == Some("rs".as_ref()) {
            let relative = path.strip_prefix(root).unwrap();
            out.push((
                relative.to_str().unwrap().to_string(),
                std::fs::read_to_string(&path).unwrap(),
            ));
        }
    }
}

fn c_string_readers(
    files: &[(String, String)],
    allowed: &[&str],
) -> Vec<String> {
    let reads = |path: &str| {
        files.iter().any(|(file, text)| {
            file.starts_with(path) && text.contains("CStr::from_ptr")
        })
    };
    let mut problems: Vec<String> = files
        .iter()
        .filter(|(file, text)| {
            text.contains("CStr::from_ptr")
                && !allowed.iter().any(|path| file.starts_with(path))
        })
        .map(|(file, _)| {
            format!(
                "{} reads a C string: take a StrArg or StrListArg block",
                file
            )
        })
        .collect();
    for path in allowed.iter().filter(|path| !reads(path)) {
        problems.push(format!(
            "{} may read C strings but reads none: remove it",
            path
        ));
    }
    problems
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

#[test]
fn no_entry_point_takes_a_name_or_value_as_a_c_string() {
    let problems = c_string_parameters(&tree(), C_STRING_PARAMETERS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_parameter_rule_refuses_a_planted_c_string() {
    let planted = fixture(
        r#"
#[no_mangle]
pub extern "C" fn planted_name(name: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn planted_list(names: *const *const c_char, n: usize) -> i32 { 0 }

macro_rules! export_c_string {
    ($name:ident) => {
        #[no_mangle]
        pub extern "C" fn $name(label: *const std::os::raw::c_char) -> i32 { 0 }
    };
}
export_c_string!(planted_by_macro);

#[no_mangle]
pub extern "C" fn exempted(value: *mut c_char) {}

#[no_mangle]
pub extern "C" fn reads(path: *const c_char, tz: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn zoned(ambiguous: *const c_char, non_existent: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn series_new_planted(name: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn blocks(name: StrArg, names: StrListArg) -> i32 { 0 }

fn internal(name: *const c_char) -> i32 { 0 }
"#,
    );
    assert_eq!(
        c_string_parameters(&planted, &["exempted", "blocks"]),
        [
            "planted_name takes name as a C string: take a StrArg or StrListArg block",
            "planted_list takes names as a C string: take a StrArg or StrListArg block",
            "planted_by_macro takes label as a C string: take a StrArg or StrListArg block",
            "blocks is exempt but takes no C string: remove its exemption",
        ]
    );
}

#[test]
fn only_the_path_zone_and_constructor_readers_read_a_c_string() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    sources_by_path(&root, &root, &mut files);
    assert!(files.len() > 50);
    let problems = c_string_readers(&files, C_STRING_READERS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_reader_rule_refuses_a_planted_c_string_read() {
    let file = |path: &str, text: &str| (path.to_string(), text.to_string());
    let files = [
        file("ffi/errors.rs", "unsafe { CStr::from_ptr(path) }"),
        file("series/constructors/primitive.rs", "CStr::from_ptr(name)"),
        file(
            "dataframe/planted.rs",
            "let s = unsafe { CStr::from_ptr(p) };",
        ),
        file("lazyframe/blocks.rs", "str_arg(p)"),
    ];
    assert_eq!(
        c_string_readers(
            &files,
            &["ffi/errors.rs", "series/constructors/", "series/stale.rs"]
        ),
        [
            "dataframe/planted.rs reads a C string: take a StrArg or StrListArg block",
            "series/stale.rs may read C strings but reads none: remove it",
        ]
    );
}
