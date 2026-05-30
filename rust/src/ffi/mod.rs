mod slices;
mod strings;

pub(crate) use self::slices::{collect_c_strings, collect_exprs};
pub(crate) use self::strings::rust_string_to_ptr;
pub use self::strings::string_drop;
