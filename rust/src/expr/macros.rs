macro_rules! expr_binop {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(
            a: *const polars::prelude::Expr,
            b: *const polars::prelude::Expr,
        ) -> *mut polars::prelude::Expr {
            if a.is_null() || b.is_null() {
                return std::ptr::null_mut();
            }
            let aa = unsafe { (*a).clone() };
            let bb = unsafe { (*b).clone() };
            let f: fn(
                polars::prelude::Expr,
                polars::prelude::Expr,
            ) -> polars::prelude::Expr = $build;
            std::boxed::Box::into_raw(std::boxed::Box::new(f(aa, bb)))
        }
    };
}

macro_rules! expr_unop {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(
            e: *const polars::prelude::Expr,
        ) -> *mut polars::prelude::Expr {
            if e.is_null() {
                return std::ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(polars::prelude::Expr) -> polars::prelude::Expr = $build;
            std::boxed::Box::into_raw(std::boxed::Box::new(f(ee)))
        }
    };
}

/// Unary aggregations that take a `ddof: u8` parameter (std, var).
macro_rules! expr_unop_u8 {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(
            e: *const polars::prelude::Expr,
            arg: u8,
        ) -> *mut polars::prelude::Expr {
            if e.is_null() {
                return std::ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(polars::prelude::Expr, u8) -> polars::prelude::Expr =
                $build;
            std::boxed::Box::into_raw(std::boxed::Box::new(f(ee, arg)))
        }
    };
}

/// Unary op carrying a single `u32` extra arg (e.g. round's decimal count).
macro_rules! expr_unop_u32 {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(
            e: *const polars::prelude::Expr,
            arg: u32,
        ) -> *mut polars::prelude::Expr {
            if e.is_null() {
                return std::ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(polars::prelude::Expr, u32) -> polars::prelude::Expr =
                $build;
            std::boxed::Box::into_raw(std::boxed::Box::new(f(ee, arg)))
        }
    };
}
