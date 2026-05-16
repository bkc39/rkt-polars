#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI32 {
    pub valid: i32,
    pub value: i32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI8 {
    pub valid: i32,
    pub value: i8,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI16 {
    pub valid: i32,
    pub value: i16,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct CompatOptF64 {
    pub valid: i32,
    pub value: f64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct CompatOptF32 {
    pub valid: i32,
    pub value: f32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI64 {
    pub valid: i32,
    pub value: i64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU8 {
    pub valid: i32,
    pub value: u8,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU16 {
    pub valid: i32,
    pub value: u16,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU32 {
    pub valid: i32,
    pub value: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU64 {
    pub valid: i32,
    pub value: u64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptBool {
    pub valid: i32,
    pub value: i32,
}

impl CompatOptI32 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: i32) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<i32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI8 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: i8) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<i8>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI16 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: i16) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<i16>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptF64 {
    pub(crate) const NONE: Self = Self {
        valid: 0,
        value: 0.0,
    };
    pub(crate) fn some(v: f64) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<f64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptF32 {
    pub(crate) const NONE: Self = Self {
        valid: 0,
        value: 0.0,
    };
    pub(crate) fn some(v: f32) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<f32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI64 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: i64) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<i64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU8 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: u8) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<u8>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU16 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: u16) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<u16>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU32 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: u32) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<u32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU64 {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: u64) -> Self {
        Self { valid: 1, value: v }
    }
    pub(crate) fn from_option(o: Option<u64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptBool {
    pub(crate) const NONE: Self = Self { valid: 0, value: 0 };
    pub(crate) fn some(v: bool) -> Self {
        Self {
            valid: 1,
            value: if v { 1 } else { 0 },
        }
    }
    pub(crate) fn from_option(o: Option<bool>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}
