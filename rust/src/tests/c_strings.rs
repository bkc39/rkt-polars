use super::guard_audit::{fixture, tree, tree_by_path, walk, Function};
use proc_macro2::{TokenStream, TokenTree};
use std::collections::BTreeSet;
use syn::visit::{self, Visit};
use syn::{FnArg, Pat, ReturnType, Type};

/// The parameters that may take a C string, by name and the prefix of the
/// export that takes them.
const C_STRING_PARAMETERS: &[(&str, &str)] = &[
    ("path", ""),
    ("tz", ""),
    ("ambiguous", ""),
    ("non_existent", ""),
    ("name", "series_new_"),
];

const C_STRING_READERS: &[&str] = &[
    "ffi/errors.rs",
    "series/time_zone.rs",
    "series/constructors/string.rs",
];

fn is_c_char(ty: &Type) -> bool {
    match ty {
        Type::Path(path) => path
            .path
            .segments
            .last()
            .is_some_and(|last| last.ident == "c_char"),
        Type::Group(group) => is_c_char(&group.elem),
        Type::Paren(paren) => is_c_char(&paren.elem),
        _ => false,
    }
}

struct CStringType<'a> {
    aliases: &'a BTreeSet<String>,
    found: bool,
}

impl<'ast> Visit<'ast> for CStringType<'_> {
    fn visit_type_ptr(&mut self, ptr: &'ast syn::TypePtr) {
        self.found |= is_c_char(&ptr.elem);
        visit::visit_type_ptr(self, ptr);
    }

    fn visit_type_path(&mut self, path: &'ast syn::TypePath) {
        self.found |=
            path.path.segments.last().is_some_and(|last| {
                self.aliases.contains(&last.ident.to_string())
            });
        visit::visit_type_path(self, path);
    }
}

fn names_a_c_string(ty: &Type, aliases: &BTreeSet<String>) -> bool {
    let mut visitor = CStringType {
        aliases,
        found: false,
    };
    visitor.visit_type(ty);
    visitor.found
}

#[derive(Default)]
struct TypeAliases(Vec<syn::ItemType>);

impl<'ast> Visit<'ast> for TypeAliases {
    fn visit_item_type(&mut self, item: &'ast syn::ItemType) {
        self.0.push(item.clone());
        visit::visit_item_type(self, item);
    }
}

/// Every `type` alias, at any depth, that names a pointer to a C string,
/// directly or through another such alias.
fn c_string_aliases(files: &[String]) -> BTreeSet<String> {
    let mut items = TypeAliases::default();
    for file in files {
        items.visit_file(&syn::parse_file(file).expect("a parsable source"));
    }
    let mut aliases = BTreeSet::new();
    loop {
        let more: Vec<String> = items
            .0
            .iter()
            .filter(|item| !aliases.contains(&item.ident.to_string()))
            .filter(|item| names_a_c_string(&item.ty, &aliases))
            .map(|item| item.ident.to_string())
            .collect();
        if more.is_empty() {
            return aliases;
        }
        aliases.extend(more);
    }
}

fn parameter_name(f: &Function, pat: &Pat) -> String {
    match pat {
        Pat::Ident(ident) => ident.ident.to_string(),
        _ => panic!("{} takes a C string through a pattern", f.name),
    }
}

fn c_string_parameter_names(
    f: &Function,
    aliases: &BTreeSet<String>,
) -> Vec<String> {
    f.inputs
        .iter()
        .filter_map(|input| match input {
            FnArg::Typed(typed) => names_a_c_string(&typed.ty, aliases)
                .then(|| parameter_name(f, &typed.pat)),
            FnArg::Receiver(_) => None,
        })
        .collect()
}

fn allows(entry: &(&str, &str), function: &str, parameter: &str) -> bool {
    entry.0 == parameter && function.starts_with(entry.1)
}

fn c_string_parameters(
    files: &[String],
    allowed: &[(&str, &str)],
) -> Vec<String> {
    let krate = walk(files);
    let aliases = c_string_aliases(files);
    let mut problems = krate.problems;
    let mut used = BTreeSet::new();
    for f in krate.functions.iter().filter(|f| f.entry) {
        for parameter in c_string_parameter_names(f, &aliases) {
            match allowed
                .iter()
                .position(|entry| allows(entry, &f.name, &parameter))
            {
                Some(i) => {
                    used.insert(i);
                }
                None => problems.push(format!(
                    "{} takes {} as a C string: take a StrArg or StrListArg block",
                    f.name, parameter
                )),
            }
        }
    }
    for (i, (parameter, prefix)) in allowed.iter().enumerate() {
        if !used.contains(&i) {
            problems.push(format!(
                "no {}* export takes {} as a C string: remove it",
                prefix, parameter
            ));
        }
    }
    problems
}

fn c_string_results(files: &[String]) -> Vec<String> {
    let krate = walk(files);
    let aliases = c_string_aliases(files);
    let mut problems = krate.problems;
    problems.extend(
        krate
            .functions
            .iter()
            .filter(|f| {
                f.entry
                    && match &f.output {
                        ReturnType::Type(_, ty) => {
                            names_a_c_string(ty, &aliases)
                        }
                        ReturnType::Default => false,
                    }
            })
            .map(|f| {
                format!("{} returns a C string: return a StrOut block", f.name)
            }),
    );
    problems
}

fn mentions_c_str(tokens: TokenStream) -> bool {
    tokens.into_iter().any(|token| match token {
        TokenTree::Ident(ident) => ident == "CStr",
        TokenTree::Group(group) => mentions_c_str(group.stream()),
        _ => false,
    })
}

fn names_c_str(text: &str) -> bool {
    mentions_c_str(text.parse().expect("a source that tokenizes"))
}

fn c_string_readers(
    files: &[(String, String)],
    allowed: &[&str],
) -> Vec<String> {
    let readers: Vec<&str> = files
        .iter()
        .filter(|(_, text)| names_c_str(text))
        .map(|(file, _)| file.as_str())
        .collect();
    let mut problems: Vec<String> = readers
        .iter()
        .filter(|file| !allowed.contains(file))
        .map(|file| {
            format!(
                "{} reads a C string: take a StrArg or StrListArg block",
                file
            )
        })
        .collect();
    for path in allowed.iter().filter(|path| !readers.contains(path)) {
        problems.push(format!(
            "{} may read C strings but names no CStr: remove it",
            path
        ));
    }
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

type Text = *mut core::ffi::c_char;

#[no_mangle]
pub extern "C" fn planted_alias() -> Text { ptr::null_mut() }

#[no_mangle]
pub extern "C" fn block() -> StrOut { ptr::null_mut() }

#[no_mangle]
pub extern "C" fn bytes() -> *const u8 { ptr::null() }

#[no_mangle]
pub extern "C" fn int8s() -> *const i8 { ptr::null() }

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
            "planted_alias returns a C string: return a StrOut block",
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

mod inner {
    pub(crate) type Label = *const core::ffi::c_char;
}
type Labels = *const inner::Label;

#[no_mangle]
pub extern "C" fn planted_alias(label: inner::Label, labels: Labels) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn reads(path: *const c_char, tz: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn zoned(ambiguous: *const c_char, non_existent: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn series_new_planted(name: *const c_char) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn blocks(name: StrArg, names: StrListArg, bytes: *const u8, data: *const i8) -> i32 { 0 }

fn internal(name: *const c_char) -> i32 { 0 }
"#,
    );
    assert_eq!(
        c_string_parameters(
            &planted,
            &[
                ("path", ""),
                ("tz", ""),
                ("ambiguous", ""),
                ("non_existent", ""),
                ("name", "series_new_"),
                ("label", "stale_"),
            ]
        ),
        [
            "planted_name takes name as a C string: take a StrArg or StrListArg block",
            "planted_list takes names as a C string: take a StrArg or StrListArg block",
            "planted_by_macro takes label as a C string: take a StrArg or StrListArg block",
            "planted_alias takes label as a C string: take a StrArg or StrListArg block",
            "planted_alias takes labels as a C string: take a StrArg or StrListArg block",
            "no stale_* export takes label as a C string: remove it",
        ]
    );
}

#[test]
#[should_panic(expected = "planted takes a C string through a pattern")]
fn the_parameter_rule_needs_a_named_c_string() {
    let planted = fixture(
        r#"
#[no_mangle]
pub extern "C" fn planted((p, _): (*const c_char, i32)) -> i32 { 0 }
"#,
    );
    c_string_parameters(&planted, &[]);
}

#[test]
fn only_the_path_zone_and_constructor_readers_read_a_c_string() {
    let files = tree_by_path();
    assert!(files.len() > 50);
    let problems = c_string_readers(&files, C_STRING_READERS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_reader_rule_refuses_a_planted_c_string_read() {
    let file = |path: &str, text: &str| (path.to_string(), text.to_string());
    let files = [
        file(
            "ffi/errors.rs",
            "fn f() { unsafe { CStr::from_ptr(path) }; }",
        ),
        file("series/spaced.rs", "fn f() { CStr :: from_ptr(p); }"),
        file("series/qualified.rs", "fn f() { <CStr>::from_ptr(p); }"),
        file(
            "series/bytes.rs",
            "fn f() { CStr::from_bytes_until_nul(b); }",
        ),
        file("series/renamed.rs", "use std::ffi::CStr as Plain;"),
        file("series/in_macro.rs", "m!(std::ffi::CStr::from_ptr(p));"),
        file("series/comment.rs", "// CStr::from_ptr\nfn f() {}"),
        file("series/literal.rs", r#"const S: &str = "CStr::from_ptr";"#),
        file("lazyframe/blocks.rs", "fn f() { str_arg(p); }"),
    ];
    assert_eq!(
        c_string_readers(&files, &["ffi/errors.rs", "series/stale.rs"]),
        [
            "series/spaced.rs reads a C string: take a StrArg or StrListArg block",
            "series/qualified.rs reads a C string: take a StrArg or StrListArg block",
            "series/bytes.rs reads a C string: take a StrArg or StrListArg block",
            "series/renamed.rs reads a C string: take a StrArg or StrListArg block",
            "series/in_macro.rs reads a C string: take a StrArg or StrListArg block",
            "series/stale.rs may read C strings but names no CStr: remove it",
        ]
    );
}
