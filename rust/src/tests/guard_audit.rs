use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

const EXEMPTIONS: &str = include_str!("unguarded.txt");

const CLASSES: &[&str] = &[
    "accessor",
    "builder",
    "compute",
    "constructor",
    "count",
    "drop",
    "error",
];

fn is_ident(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_' || c == b'$'
}

fn blank(out: &mut [u8], from: usize, to: usize) {
    let to = to.min(out.len());
    for b in &mut out[from.min(to)..to] {
        if *b != b'\n' {
            *b = b' ';
        }
    }
}

fn raw_string_open(src: &[u8], start: usize) -> Option<(usize, usize)> {
    let mut i = start + 1;
    let mut hashes = 0;
    while src.get(i) == Some(&b'#') {
        hashes += 1;
        i += 1;
    }
    (src.get(i) == Some(&b'"')).then_some((i + 1, hashes))
}

fn char_literal_end(src: &[u8], i: usize) -> Option<usize> {
    if src.get(i + 1) == Some(&b'\\') {
        src[i + 2..]
            .iter()
            .position(|&b| b == b'\'')
            .map(|p| i + 2 + p)
    } else {
        (src.get(i + 2) == Some(&b'\'')).then_some(i + 2)
    }
}

fn scrub(src: &[u8]) -> Vec<u8> {
    let mut out = src.to_vec();
    let mut i = 0;
    while i < src.len() {
        let c = src[i];
        let prev = if i == 0 { b' ' } else { src[i - 1] };
        let raw =
            raw_string_open(src, i).filter(|_| c == b'r' && !is_ident(prev));
        if src[i..].starts_with(b"//") {
            let end = src[i..]
                .iter()
                .position(|&b| b == b'\n')
                .map_or(src.len(), |p| i + p);
            blank(&mut out, i, end);
            i = end;
        } else if src[i..].starts_with(b"/*") {
            let end = src[i + 2..]
                .windows(2)
                .position(|w| w == b"*/")
                .map_or(src.len(), |p| i + 2 + p + 2);
            blank(&mut out, i, end);
            i = end;
        } else if let Some((body, hashes)) = raw {
            let mut closing = vec![b'"'];
            closing.extend(std::iter::repeat_n(b'#', hashes));
            let end = src[body..]
                .windows(closing.len())
                .position(|w| w == closing.as_slice())
                .map_or(src.len(), |p| body + p);
            blank(&mut out, body, end);
            i = end + closing.len();
        } else if c == b'"' {
            let mut j = i + 1;
            while j < src.len() && src[j] != b'"' {
                j += if src[j] == b'\\' { 2 } else { 1 };
            }
            blank(&mut out, i + 1, j);
            i = j + 1;
        } else if c == b'\'' && !is_ident(prev) {
            match char_literal_end(src, i) {
                Some(end) => {
                    blank(&mut out, i, end + 1);
                    i = end + 1;
                }
                None => i += 1,
            }
        } else {
            i += 1;
        }
    }
    out
}

fn matching(src: &[u8], open: usize) -> usize {
    let o = src[open];
    let c = match o {
        b'{' => b'}',
        b'[' => b']',
        _ => b')',
    };
    let mut depth = 0;
    for (i, &b) in src.iter().enumerate().skip(open) {
        if b == o {
            depth += 1;
        } else if b == c {
            depth -= 1;
            if depth == 0 {
                return i;
            }
        }
    }
    src.len()
}

fn keyword_at(src: &[u8], i: usize, word: &str) -> bool {
    src[i..].starts_with(word.as_bytes())
        && (i == 0 || !is_ident(src[i - 1]))
        && src.get(i + word.len()).is_none_or(|&b| !is_ident(b))
}

fn ident_after(src: &[u8], mut i: usize) -> (String, usize) {
    while src.get(i).is_some_and(u8::is_ascii_whitespace) {
        i += 1;
    }
    let start = i;
    while src.get(i).copied().is_some_and(is_ident) {
        i += 1;
    }
    (String::from_utf8_lossy(&src[start..i]).into_owned(), i)
}

struct Function {
    name: String,
    entry: bool,
    body: (usize, usize),
}

struct Macro {
    name: String,
    body: (usize, usize),
}

struct Source {
    raw: Vec<u8>,
    text: Vec<u8>,
    functions: Vec<Function>,
    macros: Vec<Macro>,
}

fn item_start(src: &[u8], at: usize) -> usize {
    src[..at]
        .iter()
        .rposition(|&b| b == b'}' || b == b';' || b == b'{')
        .map_or(0, |p| p + 1)
}

fn contains(hay: &[u8], needle: &str) -> bool {
    hay.windows(needle.len()).any(|w| w == needle.as_bytes())
}

fn body_open(text: &[u8], from: usize) -> Option<usize> {
    let mut depth = 0i32;
    for (j, &b) in text.iter().enumerate().skip(from) {
        match b {
            b'(' | b'[' => depth += 1,
            b')' | b']' => depth -= 1,
            b'{' if depth == 0 => return Some(j),
            b';' if depth == 0 => return None,
            _ => {}
        }
    }
    None
}

fn parse(src: &str) -> Source {
    let raw = src.as_bytes().to_vec();
    let text = scrub(&raw);
    let mut functions = Vec::new();
    let mut macros = Vec::new();
    for i in 0..text.len() {
        if keyword_at(&text, i, "fn") {
            let (name, after) = ident_after(&text, i + 2);
            let Some(open) =
                body_open(&text, after).filter(|_| !name.is_empty())
            else {
                continue;
            };
            let start = item_start(&text, i);
            functions.push(Function {
                name,
                entry: contains(&text[start..i], "#[no_mangle]")
                    && contains(&raw[start..i], "extern \"C\""),
                body: (open, matching(&text, open)),
            });
        } else if keyword_at(&text, i, "macro_rules") {
            let (name, after) = ident_after(&text, i + "macro_rules!".len());
            let open = after
                + text[after..]
                    .iter()
                    .position(|&b| b == b'{' || b == b'(')
                    .expect("a macro body");
            macros.push(Macro {
                name,
                body: (open, matching(&text, open)),
            });
        }
    }
    Source {
        raw,
        text,
        functions,
        macros,
    }
}

fn calls(body: &[u8], name: &str) -> bool {
    (0..body.len()).any(|i| {
        let rest = &body[i + name.len().min(body.len() - i)..];
        keyword_at(body, i, name)
            && (i == 0 || body[i - 1] != b'.')
            && (rest.starts_with(b"(") || rest.starts_with(b"::<"))
    })
}

fn invocations<'a>(text: &'a [u8], name: &str) -> Vec<&'a [u8]> {
    (0..text.len())
        .filter(|&i| {
            keyword_at(text, i, name) && text.get(i + name.len()) == Some(&b'!')
        })
        .filter_map(|i| {
            let open = i + text[i..]
                .iter()
                .position(|&b| matches!(b, b'(' | b'{' | b'['))?;
            Some(&text[open..matching(text, open)])
        })
        .collect()
}

fn guarding(sources: &[Source]) -> BTreeSet<String> {
    let mut guarding: BTreeSet<String> = ["guard_panic".to_string()].into();
    loop {
        let found: Vec<String> = sources
            .iter()
            .flat_map(|s| {
                s.functions.iter().filter_map(|f| {
                    let body = &s.text[f.body.0..f.body.1];
                    (!guarding.contains(&f.name)
                        && guarding.iter().any(|g| calls(body, g)))
                    .then(|| f.name.clone())
                })
            })
            .collect();
        if found.is_empty() {
            return guarding;
        }
        guarding.extend(found);
    }
}

#[derive(Debug, PartialEq)]
enum Exemption {
    Entry,
    Generator(usize),
}

fn exemptions(list: &str) -> Result<BTreeMap<String, Exemption>, String> {
    let mut out = BTreeMap::new();
    for line in list.lines().filter(|l| !l.trim().is_empty()) {
        let words: Vec<&str> = line.split_whitespace().collect();
        let (key, exemption, class) = match words.as_slice() {
            [name, class] => (*name, Exemption::Entry, *class),
            [name, count, class] if name.ends_with('!') => {
                let count = count
                    .parse()
                    .map_err(|_| format!("bad invocation count: {}", line))?;
                (*name, Exemption::Generator(count), *class)
            }
            _ => return Err(format!("malformed exemption: {}", line)),
        };
        if !CLASSES.contains(&class) {
            return Err(format!("unknown class {} for {}", class, key));
        }
        if out.insert(key.to_string(), exemption).is_some() {
            return Err(format!("{} is listed twice", key));
        }
    }
    Ok(out)
}

fn audit(sources: &[Source], list: &str) -> Vec<String> {
    let exempt = match exemptions(list) {
        Ok(exempt) => exempt,
        Err(err) => return vec![err],
    };
    let guarding = guarding(sources);
    let mut problems = Vec::new();
    let mut seen = BTreeSet::new();
    let entries = sources
        .iter()
        .flat_map(|s| s.functions.iter())
        .filter(|f| f.entry && !f.name.starts_with('$'));
    for f in entries {
        seen.insert(f.name.clone());
        match (guarding.contains(&f.name), exempt.get(&f.name)) {
            (false, None) => problems.push(format!(
                "{} runs outside guard_panic and is not exempt",
                f.name
            )),
            (true, Some(_)) => problems
                .push(format!("{} is guarded: remove its exemption", f.name)),
            (false, Some(Exemption::Generator(_))) => problems
                .push(format!("{} is an entry point, not a macro", f.name)),
            _ => {}
        }
    }
    for s in sources {
        for m in &s.macros {
            if !contains(&s.raw[m.body.0..m.body.1], "extern \"C\" fn") {
                continue;
            }
            let key = format!("{}!", m.name);
            seen.insert(key.clone());
            let body = &s.text[m.body.0..m.body.1];
            let guarded = |text: &[u8]| guarding.iter().any(|g| calls(text, g));
            let count = if guarded(body) {
                0
            } else {
                sources
                    .iter()
                    .flat_map(|t| invocations(&t.text, &m.name))
                    .filter(|args| !guarded(args))
                    .count()
            };
            match (count, exempt.get(&key)) {
                (0, None) => {}
                (_, None) => problems.push(format!(
                    "{} ({} unguarded invocations) generates entry points outside guard_panic and is not exempt",
                    key, count
                )),
                (0, Some(_)) => problems
                    .push(format!("{} is guarded: remove its exemption", key)),
                (_, Some(Exemption::Generator(listed))) if *listed != count => {
                    problems.push(format!(
                        "{} has {} unguarded invocations, the exemption lists {}",
                        key, count, listed
                    ))
                }
                (_, Some(Exemption::Entry)) => problems.push(format!(
                    "{} generates entry points: list it as `{} <count> <class>`",
                    key, key
                )),
                _ => {}
            }
        }
    }
    for key in exempt.keys().filter(|k| !seen.contains(*k)) {
        problems.push(format!("{} is exempt but is not an entry point", key));
    }
    problems
}

fn crate_sources(dir: &Path, out: &mut Vec<Source>) {
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
            out.push(parse(&std::fs::read_to_string(&path).unwrap()));
        }
    }
}

fn tree() -> Vec<Source> {
    let mut sources = Vec::new();
    crate_sources(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("src"),
        &mut sources,
    );
    sources
}

#[test]
fn every_entry_point_runs_under_guard_panic_or_is_exempt() {
    let problems = audit(&tree(), EXEMPTIONS);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_audit_reads_every_entry_point() {
    let sources = tree();
    let entries: BTreeSet<&str> = sources
        .iter()
        .flat_map(|s| s.functions.iter())
        .filter(|f| f.entry)
        .map(|f| f.name.as_str())
        .collect();
    assert!(entries.len() > 200, "{} entry points", entries.len());
    let guarding = guarding(&sources);
    for name in [
        "dataframe_to_string",
        "expr_to_string",
        "lazyframe_collect",
        "dataframe_write_csv_with_options",
    ] {
        assert!(entries.contains(name), "{} not found", name);
        assert!(guarding.contains(name), "{} not guarded", name);
    }
    assert!(entries.contains("series_len"));
    assert!(!guarding.contains("series_len"));
}

#[test]
fn the_audit_fails_on_a_new_unguarded_entry_point() {
    let source = parse(concat!(
        "#[no_mangle]\n",
        "pub extern \"C\" fn guarded(df: *mut DataFrame) -> *const c_char {\n",
        "    let s = \"} { fn fake() {\";\n",
        "    let c = '{';\n",
        "    guard_panic(|| Some(format!(\"{}\", s))).map_or(ptr::null(), f)\n",
        "}\n",
        "fn helper<'a>() -> Option<&'a ()> { guard_panic(|| None) }\n",
        "#[no_mangle]\n",
        "pub extern \"C\" fn through_helper() { helper(); }\n",
        "#[no_mangle]\n",
        "pub extern \"C\" fn method_call(x: X) { x.helper(); }\n",
        "// #[no_mangle] pub extern \"C\" fn commented() {}\n",
        "macro_rules! generate {\n",
        "    ($name:ident) => {\n",
        "        #[no_mangle]\n",
        "        pub extern \"C\" fn $name() {}\n",
        "    };\n",
        "}\n",
        "generate!(one);\n",
        "generate!(two);\n",
        "generate!(three, helper());\n",
    ));
    let sources = [source];
    assert_eq!(
        audit(&sources, ""),
        vec![
            "method_call runs outside guard_panic and is not exempt",
            "generate! (2 unguarded invocations) generates entry points outside guard_panic and is not exempt",
        ]
    );
    assert_eq!(
        audit(&sources, "method_call compute\ngenerate! 2 builder\n"),
        Vec::<String>::new()
    );
    assert_eq!(
        audit(&sources, "method_call compute\ngenerate! 1 builder\n"),
        vec!["generate! has 2 unguarded invocations, the exemption lists 1"]
    );
    assert_eq!(
        audit(
            &sources,
            "method_call compute\ngenerate! 2 builder\nguarded drop\ngone drop\n"
        ),
        vec![
            "guarded is guarded: remove its exemption",
            "gone is exempt but is not an entry point",
        ]
    );
    assert_eq!(
        audit(&sources, "method_call sometimes\n"),
        vec!["unknown class sometimes for method_call"]
    );
}
