use proc_macro2::{Delimiter, Group, Ident, TokenStream, TokenTree};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use syn::parse::{ParseStream, Parser};
use syn::visit::{self, Visit};
use syn::{Attribute, Block, Expr, Item, Meta, Pat, Stmt};

const EXEMPTIONS: &str = include_str!("unguarded.txt");

const CLASSES: &[&str] = &[
    "accessor",
    "builder",
    "constructor",
    "count",
    "drop",
    "error",
    "todo-129",
];

const MAX_DEPTH: usize = 32;

struct Arm {
    pattern: Vec<TokenTree>,
    body: TokenStream,
}

struct Function {
    name: String,
    entry: bool,
    block: Block,
}

#[derive(Default)]
struct Crate {
    functions: Vec<Function>,
    problems: Vec<String>,
}

type Bindings = BTreeMap<String, (String, Vec<TokenTree>)>;

fn trees(stream: TokenStream) -> Vec<TokenTree> {
    stream.into_iter().collect()
}

/// syn 2.0.72 cannot parse `#[unsafe(attr)]`, so the audit reads it as `#[attr]`.
fn safe_attributes(stream: TokenStream) -> TokenStream {
    let mut after_hash = false;
    stream
        .into_iter()
        .map(|tree| {
            let tree = match tree {
                TokenTree::Group(g) => {
                    let inner = trees(g.stream());
                    let unwrapped = match &inner[..] {
                        [TokenTree::Ident(u), TokenTree::Group(args)]
                            if after_hash
                                && g.delimiter() == Delimiter::Bracket
                                && u == "unsafe"
                                && args.delimiter()
                                    == Delimiter::Parenthesis =>
                        {
                            args.stream()
                        }
                        _ => inner.into_iter().collect(),
                    };
                    let mut group =
                        Group::new(g.delimiter(), safe_attributes(unwrapped));
                    group.set_span(g.span());
                    TokenTree::Group(group)
                }
                tree => tree,
            };
            after_hash = match &tree {
                TokenTree::Punct(p) => {
                    p.as_char() == '#' || (after_hash && p.as_char() == '!')
                }
                _ => false,
            };
            tree
        })
        .collect()
}

fn is_punct(tree: Option<&TokenTree>, c: char) -> bool {
    matches!(tree, Some(TokenTree::Punct(p)) if p.as_char() == c)
}

fn arms(name: &str, tokens: TokenStream) -> Result<Vec<Arm>, String> {
    let mut out = Vec::new();
    let tokens = trees(tokens);
    let mut i = 0;
    while i < tokens.len() {
        let (Some(TokenTree::Group(pattern)), Some(TokenTree::Group(body))) =
            (tokens.get(i), tokens.get(i + 3))
        else {
            return Err(format!("{}! has an arm the audit cannot read", name));
        };
        if !is_punct(tokens.get(i + 1), '=')
            || !is_punct(tokens.get(i + 2), '>')
        {
            return Err(format!("{}! has an arm the audit cannot read", name));
        }
        out.push(Arm {
            pattern: trees(pattern.stream()),
            body: body.stream(),
        });
        i += if is_punct(tokens.get(i + 4), ';') {
            5
        } else {
            4
        };
    }
    Ok(out)
}

fn same_token(a: &TokenTree, b: &TokenTree) -> bool {
    match (a, b) {
        (TokenTree::Ident(x), TokenTree::Ident(y)) => x == y,
        (TokenTree::Punct(x), TokenTree::Punct(y)) => {
            x.as_char() == y.as_char()
        }
        (TokenTree::Literal(x), TokenTree::Literal(y)) => {
            x.to_string() == y.to_string()
        }
        _ => false,
    }
}

fn parsed<T: syn::parse::Parse>(s: ParseStream) -> syn::Result<()> {
    s.parse::<T>().map(drop)
}

fn pattern(s: ParseStream) -> syn::Result<()> {
    Pat::parse_multi_with_leading_vert(s).map(drop)
}

fn pattern_param(s: ParseStream) -> syn::Result<()> {
    Pat::parse_single(s).map(drop)
}

fn fragment(kind: &str, input: &[TokenTree]) -> Option<usize> {
    let parse: fn(ParseStream) -> syn::Result<()> = match kind {
        "ident" => {
            return matches!(input.first(), Some(TokenTree::Ident(_)))
                .then_some(1)
        }
        "tt" => return input.first().map(|_| 1),
        "lifetime" => {
            return (is_punct(input.first(), '\'')
                && matches!(input.get(1), Some(TokenTree::Ident(_))))
            .then_some(2)
        }
        "expr" => parsed::<Expr>,
        "ty" => parsed::<syn::Type>,
        "path" => parsed::<syn::Path>,
        "pat" => pattern,
        "pat_param" => pattern_param,
        "block" => parsed::<Block>,
        "item" => parsed::<Item>,
        "stmt" => parsed::<Stmt>,
        "vis" => parsed::<syn::Visibility>,
        "literal" => parsed::<syn::Lit>,
        "meta" => parsed::<Meta>,
        _ => return None,
    };
    let rest = (|s: ParseStream| {
        parse(s)?;
        s.parse::<TokenStream>()
    })
    .parse2(input.iter().cloned().collect())
    .ok()?;
    Some(input.len() - rest.into_iter().count())
}

fn match_arm(
    pattern: &[TokenTree],
    input: &[TokenTree],
    binds: &mut Bindings,
) -> Result<bool, String> {
    let mut at = 0;
    let mut i = 0;
    while i < pattern.len() {
        match (&pattern[i], pattern.get(i + 1)) {
            (TokenTree::Punct(p), Some(TokenTree::Ident(var)))
                if p.as_char() == '$' =>
            {
                let Some(TokenTree::Ident(kind)) = pattern
                    .get(i + 3)
                    .filter(|_| is_punct(pattern.get(i + 2), ':'))
                else {
                    return Err(format!("${} has no fragment specifier", var));
                };
                let kind = kind.to_string();
                let Some(n) = fragment(&kind, &input[at..]) else {
                    return Ok(false);
                };
                binds.insert(
                    var.to_string(),
                    (kind, input[at..at + n].to_vec()),
                );
                at += n;
                i += 4;
            }
            (TokenTree::Punct(p), Some(TokenTree::Group(_)))
                if p.as_char() == '$' =>
            {
                return Err("a repetition".to_string());
            }
            (TokenTree::Group(g), _) => {
                let Some(TokenTree::Group(h)) = input.get(at) else {
                    return Ok(false);
                };
                if g.delimiter() != h.delimiter()
                    || !match_arm(
                        &trees(g.stream()),
                        &trees(h.stream()),
                        binds,
                    )?
                {
                    return Ok(false);
                }
                at += 1;
                i += 1;
            }
            (token, _) => {
                if !input.get(at).is_some_and(|t| same_token(token, t)) {
                    return Ok(false);
                }
                at += 1;
                i += 1;
            }
        }
    }
    Ok(at == input.len())
}

fn transcribe(
    body: TokenStream,
    binds: &Bindings,
) -> Result<TokenStream, String> {
    let body = trees(body);
    let mut out = Vec::new();
    let mut i = 0;
    while i < body.len() {
        match (&body[i], body.get(i + 1)) {
            (TokenTree::Punct(p), Some(TokenTree::Ident(var)))
                if p.as_char() == '$' =>
            {
                if var == "crate" {
                    out.push(TokenTree::Ident(Ident::new("crate", var.span())));
                } else {
                    let Some((kind, tokens)) = binds.get(&var.to_string())
                    else {
                        return Err(format!("${} is unbound", var));
                    };
                    let tokens = tokens.iter().cloned();
                    if kind == "expr" {
                        out.push(TokenTree::Group(Group::new(
                            Delimiter::None,
                            tokens.collect(),
                        )));
                    } else {
                        out.extend(tokens);
                    }
                }
                i += 2;
            }
            (TokenTree::Punct(p), Some(TokenTree::Group(_)))
                if p.as_char() == '$' =>
            {
                return Err("a repetition".to_string());
            }
            (TokenTree::Group(g), _) => {
                out.push(TokenTree::Group(Group::new(
                    g.delimiter(),
                    transcribe(g.stream(), binds)?,
                )));
                i += 1;
            }
            (token, _) => {
                out.push(token.clone());
                i += 1;
            }
        }
    }
    Ok(out.into_iter().collect())
}

fn expand(
    name: &str,
    arms: &[Arm],
    tokens: TokenStream,
) -> Result<TokenStream, String> {
    let input = trees(tokens.clone());
    for arm in arms {
        let mut binds = Bindings::new();
        if match_arm(&arm.pattern, &input, &mut binds)? {
            return transcribe(arm.body.clone(), &binds);
        }
    }
    Err(format!("no arm of {}! matches `{}`", name, tokens))
}

fn mentions_export(tokens: TokenStream) -> bool {
    tokens.into_iter().any(|t| match t {
        TokenTree::Ident(i) => i == "no_mangle" || i == "export_name",
        TokenTree::Group(g) => mentions_export(g.stream()),
        _ => false,
    })
}

fn export_meta(meta: &Meta) -> Option<Option<String>> {
    match meta {
        Meta::Path(p) if p.is_ident("no_mangle") => Some(None),
        Meta::NameValue(nv) if nv.path.is_ident("export_name") => {
            match &nv.value {
                Expr::Lit(syn::ExprLit {
                    lit: syn::Lit::Str(s),
                    ..
                }) => Some(Some(s.value())),
                _ => Some(None),
            }
        }
        _ => None,
    }
}

fn export(attrs: &[Attribute]) -> Option<Option<String>> {
    attrs.iter().find_map(|a| export_meta(&a.meta))
}

#[derive(Default)]
struct Definitions {
    macros: BTreeMap<String, Vec<Arm>>,
    problems: Vec<String>,
}

impl<'ast> Visit<'ast> for Definitions {
    fn visit_item_macro(&mut self, m: &'ast syn::ItemMacro) {
        let Some(name) = m.ident.as_ref().map(Ident::to_string) else {
            return;
        };
        match arms(&name, m.mac.tokens.clone()) {
            Ok(arms) => {
                if self.macros.insert(name.clone(), arms).is_some() {
                    self.problems.push(format!("{}! is defined twice", name));
                }
            }
            Err(err) => self.problems.push(err),
        }
    }
}

struct Walker<'a> {
    macros: &'a BTreeMap<String, Vec<Arm>>,
    depth: usize,
    out: &'a mut Crate,
}

impl Walker<'_> {
    fn function(
        &mut self,
        attrs: &[Attribute],
        sig: &syn::Signature,
        block: &Block,
    ) {
        let export = export(attrs);
        let foreign = sig.abi.as_ref().is_some_and(|abi| {
            abi.name.as_ref().is_none_or(|n| n.value() != "Rust")
        });
        let name = match &export {
            Some(Some(name)) => name.clone(),
            _ => sig.ident.to_string(),
        };
        self.out.functions.push(Function {
            name,
            entry: export.is_some() && foreign,
            block: block.clone(),
        });
    }

    fn expand_into(&mut self, name: &str, arms: &[Arm], tokens: TokenStream) {
        if self.depth >= MAX_DEPTH {
            self.out
                .problems
                .push(format!("{}! expands past depth {}", name, MAX_DEPTH));
            return;
        }
        let stream = match expand(name, arms, tokens) {
            Ok(stream) => stream,
            Err(err) => {
                self.out.problems.push(format!(
                    "{}!: the audit cannot expand {}",
                    name, err
                ));
                return;
            }
        };
        self.depth += 1;
        let stream = safe_attributes(stream);
        if let Ok(file) = syn::parse2::<syn::File>(stream.clone()) {
            self.visit_file(&file);
        } else if let Ok(stmts) = Block::parse_within.parse2(stream) {
            for stmt in &stmts {
                self.visit_stmt(stmt);
            }
        } else {
            self.out.problems.push(format!(
                "{}! expands to tokens the audit cannot parse",
                name
            ));
        }
        self.depth -= 1;
    }
}

impl<'ast> Visit<'ast> for Walker<'_> {
    fn visit_item_fn(&mut self, f: &'ast syn::ItemFn) {
        self.function(&f.attrs, &f.sig, &f.block);
        visit::visit_item_fn(self, f);
    }

    fn visit_impl_item_fn(&mut self, f: &'ast syn::ImplItemFn) {
        self.function(&f.attrs, &f.sig, &f.block);
        visit::visit_impl_item_fn(self, f);
    }

    fn visit_item_macro(&mut self, m: &'ast syn::ItemMacro) {
        if m.ident.is_none() {
            self.visit_macro(&m.mac);
        }
    }

    fn visit_macro(&mut self, m: &'ast syn::Macro) {
        let name = m
            .path
            .segments
            .last()
            .map_or_else(String::new, |s| s.ident.to_string());
        let macros = self.macros;
        match macros.get(&name) {
            Some(arms) => self.expand_into(&name, arms, m.tokens.clone()),
            None if mentions_export(m.tokens.clone()) => {
                self.out.problems.push(format!(
                    "{}! wraps an entry point the audit cannot expand",
                    name
                ))
            }
            None => {}
        }
    }
}

fn walk(files: &[String]) -> Crate {
    let mut out = Crate::default();
    let parsed: Vec<syn::File> = files
        .iter()
        .filter_map(|text| {
            match text
                .parse::<TokenStream>()
                .map_err(syn::Error::from)
                .and_then(|stream| {
                    syn::parse2::<syn::File>(safe_attributes(stream))
                }) {
                Ok(file) => Some(file),
                Err(err) => {
                    out.problems
                        .push(format!("a source file does not parse: {}", err));
                    None
                }
            }
        })
        .collect();
    let mut definitions = Definitions::default();
    for file in &parsed {
        definitions.visit_file(file);
    }
    out.problems.append(&mut definitions.problems);
    let mut walker = Walker {
        macros: &definitions.macros,
        depth: 0,
        out: &mut out,
    };
    for file in &parsed {
        walker.visit_file(file);
    }
    out
}

fn bind(pat: &Pat, locals: &mut BTreeSet<String>) {
    match pat {
        Pat::Ident(p) => {
            locals.insert(p.ident.to_string());
        }
        Pat::TupleStruct(p) => p.elems.iter().for_each(|e| bind(e, locals)),
        Pat::Tuple(p) => p.elems.iter().for_each(|e| bind(e, locals)),
        Pat::Type(p) => bind(&p.pat, locals),
        _ => {}
    }
}

fn guarded_block(block: &Block, guarding: &BTreeSet<String>) -> bool {
    let mut locals = BTreeSet::new();
    let last = block.stmts.len().checked_sub(1);
    for (i, stmt) in block.stmts.iter().enumerate() {
        match stmt {
            Stmt::Local(local) => {
                let flows = local
                    .init
                    .as_ref()
                    .is_some_and(|init| guarded(&init.expr, guarding, &locals));
                let mut names = BTreeSet::new();
                bind(&local.pat, &mut names);
                if flows {
                    locals.extend(names);
                } else {
                    locals.retain(|name| !names.contains(name));
                }
            }
            Stmt::Expr(tail, None) if Some(i) == last => {
                return guarded(tail, guarding, &locals);
            }
            _ => {}
        }
    }
    false
}

fn guarded(
    e: &Expr,
    guarding: &BTreeSet<String>,
    locals: &BTreeSet<String>,
) -> bool {
    let inner = |e: &Expr| guarded(e, guarding, locals);
    match e {
        Expr::Call(call) => {
            let callee =
                match &*call.func {
                    Expr::Path(p) => p.path.segments.last().is_some_and(|s| {
                        guarding.contains(&s.ident.to_string())
                    }),
                    _ => false,
                };
            callee || call.args.iter().any(inner)
        }
        Expr::MethodCall(call) => {
            inner(&call.receiver)
                || call.args.iter().any(|arg| match arg {
                    Expr::Closure(closure) => inner(&closure.body),
                    arg => inner(arg),
                })
        }
        Expr::Path(p) => p
            .path
            .get_ident()
            .is_some_and(|i| locals.contains(&i.to_string())),
        Expr::Match(m) => inner(&m.expr),
        Expr::Paren(p) => inner(&p.expr),
        Expr::Group(g) => inner(&g.expr),
        Expr::Block(b) => guarded_block(&b.block, guarding),
        Expr::Unsafe(u) => guarded_block(&u.block, guarding),
        _ => false,
    }
}

fn guarding(functions: &[Function]) -> BTreeSet<String> {
    let mut set: BTreeSet<String> = ["guard_panic".to_string()].into();
    loop {
        let mut by_name: BTreeMap<&str, bool> = BTreeMap::new();
        for f in functions {
            let g = guarded_block(&f.block, &set);
            by_name
                .entry(&f.name)
                .and_modify(|all| *all &= g)
                .or_insert(g);
        }
        let found: Vec<String> = by_name
            .into_iter()
            .filter(|(name, g)| *g && !set.contains(*name))
            .map(|(name, _)| name.to_string())
            .collect();
        if found.is_empty() {
            return set;
        }
        set.extend(found);
    }
}

fn class_by_name(name: &str) -> Option<&'static str> {
    if name.ends_with("_drop_count") {
        Some("count")
    } else if name.ends_with("_drop") {
        Some("drop")
    } else {
        None
    }
}

fn exemptions(list: &str) -> Result<BTreeMap<String, String>, String> {
    let mut out = BTreeMap::new();
    for line in list.lines().filter(|l| !l.trim().is_empty()) {
        let [name, class] = line.split_whitespace().collect::<Vec<_>>()[..]
        else {
            return Err(format!("malformed exemption: {}", line));
        };
        if !CLASSES.contains(&class) {
            return Err(format!("unknown class {} for {}", class, name));
        }
        let claimed = matches!(class, "drop" | "count").then_some(class);
        if class_by_name(name) != claimed {
            return Err(format!("{} does not fit class {}", name, class));
        }
        if out.insert(name.to_string(), class.to_string()).is_some() {
            return Err(format!("{} is listed twice", name));
        }
    }
    Ok(out)
}

fn audit(files: &[String], list: &str) -> Vec<String> {
    let exempt = match exemptions(list) {
        Ok(exempt) => exempt,
        Err(err) => return vec![err],
    };
    let krate = walk(files);
    let guarding = guarding(&krate.functions);
    let mut problems = krate.problems;
    let mut seen = BTreeSet::new();
    for f in krate.functions.iter().filter(|f| f.entry) {
        if !seen.insert(f.name.clone()) {
            problems.push(format!("{} is exported twice", f.name));
            continue;
        }
        match (
            guarded_block(&f.block, &guarding),
            exempt.contains_key(&f.name),
        ) {
            (false, false) => problems.push(format!(
                "{} runs outside guard_panic and is not exempt",
                f.name
            )),
            (true, true) => problems
                .push(format!("{} is guarded: remove its exemption", f.name)),
            _ => {}
        }
    }
    for name in exempt.keys().filter(|k| !seen.contains(*k)) {
        problems.push(format!("{} is exempt but is not an entry point", name));
    }
    problems
}

fn crate_sources(dir: &Path, out: &mut Vec<String>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .expect("readable source directory")
        .map(|e| e.expect("directory entry").path())
        .collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            if path.file_name() != Some("tests".as_ref()) {
                crate_sources(&path, out);
            }
        } else if path.extension() == Some("rs".as_ref()) {
            out.push(std::fs::read_to_string(&path).unwrap());
        }
    }
}

fn tree() -> Vec<String> {
    let mut sources = Vec::new();
    crate_sources(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("src"),
        &mut sources,
    );
    sources
}

fn fixture(text: &str) -> Vec<String> {
    vec![text.to_string()]
}

#[test]
fn every_entry_point_runs_under_guard_panic_or_is_exempt() {
    let problems = audit(&tree(), EXEMPTIONS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_audit_reads_every_entry_point() {
    let krate = walk(&tree());
    assert_eq!(krate.problems, Vec::<String>::new());
    let guarding = guarding(&krate.functions);
    let entry = |name: &str| {
        krate
            .functions
            .iter()
            .find(|f| f.entry && f.name == name)
            .unwrap_or_else(|| panic!("{} not found", name))
    };
    for name in [
        "dataframe_to_string",
        "lazyframe_collect",
        "dataframe_write_csv_with_options",
        "dataframe_read_csv_v2",
        "series_cast",
    ] {
        assert!(
            guarded_block(&entry(name).block, &guarding),
            "{} not guarded",
            name
        );
    }
    for name in ["series_len", "series_add_i32", "expr_sum"] {
        assert!(
            !guarded_block(&entry(name).block, &guarding),
            "{} guarded",
            name
        );
    }
}

#[test]
fn the_audit_accepts_the_guarded_shapes() {
    let source = fixture(
        r#"
#[no_mangle]
pub extern "C" fn direct(df: *mut DataFrame) -> *const c_char {
    clear_last_error();
    let s = "} { fn fake() {";
    let c = '{';
    guard_panic(|| Some(format!("{}", s))).map_or(ptr::null(), f)
}

fn helper(path: *const c_char) -> Option<()> {
    decode(path).and_then(|p| guard_panic(|| read(p)))
}

#[no_mangle]
pub extern "C" fn through_a_helper(path: *const c_char) -> i32 {
    helper(path).map_or(1, |_| 0)
}

#[no_mangle]
pub extern "C" fn through_a_local() -> i32 {
    let Some(x) = guard_panic(|| work()) else {
        return 1;
    };
    finish(x)
}

macro_rules! entry {
    ($name:ident -> $out:ty, |$p:ident| $body:expr) => {
        #[no_mangle]
        pub extern "C" fn $name($p: i32) -> $out {
            $body
        }
    };
}

entry!(through_its_invocation -> i32, |p| {
    guard_panic(|| work(p)).unwrap_or(0)
});
"#,
    );
    assert_eq!(audit(&source, ""), Vec::<String>::new());
}

#[test]
fn the_audit_counts_entry_points_of_nested_generators() {
    let source = fixture(
        r#"
macro_rules! scalar {
    ($name:ident, $ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $name(rhs: $ty) {}
    };
}

macro_rules! family {
    ($ty:ty, $add:ident, $sub:ident) => {
        scalar!($add, $ty);
        scalar!($sub, $ty);
    };
}

family!(i32, add_i32, sub_i32);
family!(Vec<(i16, u8)>, add_i16, sub_i16);
"#,
    );
    let listed = "add_i32 todo-129\nsub_i32 todo-129\n";
    assert_eq!(
        audit(&source, listed),
        vec![
            "add_i16 runs outside guard_panic and is not exempt",
            "sub_i16 runs outside guard_panic and is not exempt",
        ]
    );
}

#[test]
fn the_audit_reads_every_export_attribute() {
    let source = fixture(
        r#"
#[unsafe(no_mangle)]
pub extern "C" fn spelled_unsafe() {}

#[export_name = "exported"]
pub extern "C" fn internal_name() {}

#[unsafe(export_name = "exported_unsafely")]
pub extern "C" fn other_internal_name() {}

#[no_mangle]
pub extern "C-unwind" fn unwinding() {}

#[no_mangle]
pub fn rust_abi() {}
"#,
    );
    assert_eq!(
        audit(&source, ""),
        vec![
            "spelled_unsafe runs outside guard_panic and is not exempt",
            "exported runs outside guard_panic and is not exempt",
            "exported_unsafely runs outside guard_panic and is not exempt",
            "unwinding runs outside guard_panic and is not exempt",
        ]
    );
}

#[test]
fn the_audit_is_not_fooled_by_literals() {
    let source = fixture(
        r##"
fn quote() -> u8 {
    b'"'
}

#[no_mangle]
pub extern "C" fn after_a_byte_literal() {}

fn raw() -> &'static str {
    r#"" guard_panic(|| "#
}

#[no_mangle]
pub extern "C" fn after_a_raw_string() {}

// #[no_mangle] pub extern "C" fn commented() {}
"##,
    );
    assert_eq!(
        audit(&source, ""),
        vec![
            "after_a_byte_literal runs outside guard_panic and is not exempt",
            "after_a_raw_string runs outside guard_panic and is not exempt",
        ]
    );
}

#[test]
fn the_audit_refuses_an_incidental_guard() {
    let source = fixture(
        r#"
#[no_mangle]
pub extern "C" fn guard_then_work() -> i32 {
    guard_panic(|| Some(()));
    work()
}

#[no_mangle]
pub extern "C" fn guard_discarded() -> i32 {
    let _ = guard_panic(|| Some(()));
    work()
}

#[no_mangle]
pub extern "C" fn guard_in_a_branch(flag: bool) -> i32 {
    if flag {
        guard_panic(|| work())
    } else {
        work()
    }
}

#[no_mangle]
pub extern "C" fn method_named_like_a_helper(x: X) -> i32 {
    x.guard_panic(|| work())
}

#[no_mangle]
pub extern "C" fn guard_shadowed(s: S, dt: D) -> *mut Series {
    let out = guard_panic(|| Some(1));
    let out = s.cast(&dt).unwrap();
    Box::into_raw(Box::new(out))
}
"#,
    );
    assert_eq!(
        audit(&source, ""),
        vec![
            "guard_then_work runs outside guard_panic and is not exempt",
            "guard_discarded runs outside guard_panic and is not exempt",
            "guard_in_a_branch runs outside guard_panic and is not exempt",
            "method_named_like_a_helper runs outside guard_panic and is not exempt",
            "guard_shadowed runs outside guard_panic and is not exempt",
        ]
    );
}

#[test]
fn the_audit_expands_the_arm_an_invocation_matches() {
    let source = fixture(
        r#"
macro_rules! two_arms {
    (guarded $name:ident) => {
        #[no_mangle]
        pub extern "C" fn $name() -> Option<i32> {
            guard_panic(|| work())
        }
    };
    (bare $name:ident) => {
        #[no_mangle]
        pub extern "C" fn $name() -> Option<i32> {
            work()
        }
    };
}

two_arms!(guarded first);
two_arms!(bare second);

macro_rules! entry {
    ($name:ident, |$p:ident| $body:expr) => {
        #[no_mangle]
        pub extern "C" fn $name($p: i32) -> i32 {
            $body
        }
    };
}

entry!(guarded_body, |p| guard_panic(|| work(p)).unwrap_or(0));
entry!(bare_body, |p| work(p));
"#,
    );
    assert_eq!(
        audit(&source, ""),
        vec![
            "second runs outside guard_panic and is not exempt",
            "bare_body runs outside guard_panic and is not exempt",
        ]
    );
}

#[test]
fn the_audit_reports_what_it_cannot_expand() {
    let source = fixture(
        r#"
macro_rules! many {
    ($($name:ident),*) => {
        $(
            #[no_mangle]
            pub extern "C" fn $name() {}
        )*
    };
}

many!(a, b);

paste! {
    #[no_mangle]
    pub extern "C" fn hidden() {}
}

macro_rules! forever {
    ($name:ident) => {
        forever!($name);
    };
}

forever!(again);
"#,
    );
    assert_eq!(
        audit(&source, ""),
        vec![
            "many!: the audit cannot expand a repetition",
            "paste! wraps an entry point the audit cannot expand",
            "forever! expands past depth 32",
        ]
    );
}

#[test]
fn the_audit_checks_the_exemption_list() {
    let source = fixture(
        r#"
#[no_mangle]
pub extern "C" fn bare() {}

#[no_mangle]
pub extern "C" fn guarded() -> Option<()> {
    guard_panic(|| work())
}

#[no_mangle]
pub extern "C" fn thing_drop() {}
"#,
    );
    assert_eq!(
        audit(&source, "bare todo-129\nthing_drop drop\n"),
        Vec::<String>::new()
    );
    assert_eq!(
        audit(
            &source,
            "bare todo-129\nthing_drop drop\nguarded builder\ngone accessor\n"
        ),
        vec![
            "guarded is guarded: remove its exemption",
            "gone is exempt but is not an entry point",
        ]
    );
    for (list, problem) in [
        ("bare sometimes\n", "unknown class sometimes for bare"),
        ("bare drop\n", "bare does not fit class drop"),
        (
            "thing_drop builder\n",
            "thing_drop does not fit class builder",
        ),
        (
            "thing_drop_count drop\n",
            "thing_drop_count does not fit class drop",
        ),
        ("bare builder\nbare builder\n", "bare is listed twice"),
        ("bare 3 builder\n", "malformed exemption: bare 3 builder"),
    ] {
        assert_eq!(audit(&source, list), vec![problem], "{}", list);
    }
}
