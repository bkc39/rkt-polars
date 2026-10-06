use super::*;

fn dtype(tag: CompatDTypeTag, tu: CompatTimeUnit) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: tu as i32,
        flags: 0,
        array_width: 0,
    }
}

fn literal(value: i64, target: CompatDType) -> Expr {
    let e = expr_lit_temporal(value, target);
    assert!(!e.is_null(), "no literal for {value} as {target:?}");
    let out = unsafe { (*e).clone() };
    expr_drop(e);
    out
}

fn evaluate(e: Expr) -> Series {
    DataFrame::new_infer_height(vec![Column::new("x".into(), [0i32])])
        .unwrap()
        .lazy()
        .select([e.alias("v")])
        .collect()
        .unwrap()
        .column("v")
        .unwrap()
        .as_materialized_series()
        .clone()
}

fn physical(s: &Series) -> Option<i64> {
    s.to_physical_repr()
        .cast(&DataType::Int64)
        .unwrap()
        .i64()
        .unwrap()
        .get(0)
}

#[test]
fn temporal_literal_has_dtype_and_physical_value() {
    use CompatDTypeTag as Tag;
    use CompatTimeUnit as Unit;
    let cases = [
        (15887, dtype(Tag::Date, Unit::None), DataType::Date),
        (-1, dtype(Tag::Date, Unit::None), DataType::Date),
        (
            1_500,
            dtype(Tag::Datetime, Unit::Microseconds),
            DataType::Datetime(TimeUnit::Microseconds, None),
        ),
        (
            -1,
            dtype(Tag::Datetime, Unit::Nanoseconds),
            DataType::Datetime(TimeUnit::Nanoseconds, None),
        ),
        (
            -250,
            dtype(Tag::Duration, Unit::Milliseconds),
            DataType::Duration(TimeUnit::Milliseconds),
        ),
        (
            3_600_000_000_001,
            dtype(Tag::Time, Unit::None),
            DataType::Time,
        ),
    ];
    for (value, target, expected) in cases {
        let s = evaluate(literal(value, target));
        assert_eq!(s.dtype(), &expected);
        assert_eq!(physical(&s), Some(value));
    }
}

#[test]
fn temporal_literal_refuses_other_dtypes_and_out_of_range_values() {
    use CompatDTypeTag as Tag;
    use CompatTimeUnit as Unit;
    let refused = [
        (1, dtype(Tag::Int64, Unit::None)),
        (1, dtype(Tag::String, Unit::None)),
        (i64::from(i32::MAX) + 1, dtype(Tag::Date, Unit::None)),
        (-1, dtype(Tag::Time, Unit::None)),
        (86_400_000_000_000, dtype(Tag::Time, Unit::None)),
    ];
    for (value, target) in refused {
        assert!(
            expr_lit_temporal(value, target).is_null(),
            "{value} as {target:?}"
        );
    }
}

#[test]
fn temporal_literal_compares_with_a_column() {
    let days = Series::new("d".into(), [15886i32, 15887, 15888])
        .cast(&DataType::Date)
        .unwrap();
    let date =
        literal(15887, dtype(CompatDTypeTag::Date, CompatTimeUnit::None));
    let after = DataFrame::new_infer_height(vec![days.into()])
        .unwrap()
        .lazy()
        .filter(col("d").gt_eq(date))
        .collect()
        .unwrap();
    assert_eq!(after.height(), 2);
}
