#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct YMD {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptYMD {
    pub valid: i32,
    pub value: YMD,
}

impl CompatOptYMD {
    pub(crate) const NONE: Self = Self {
        valid: 0,
        value: YMD {
            year: 0,
            month: 0,
            day: 0,
        },
    };

    pub(crate) fn some(v: YMD) -> Self {
        Self { valid: 1, value: v }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct YMDHMS {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptYMDHMS {
    pub valid: i32,
    pub value: YMDHMS,
}

impl CompatOptYMDHMS {
    pub(crate) const NONE: Self = Self {
        valid: 0,
        value: YMDHMS {
            year: 0,
            month: 0,
            day: 0,
            hour: 0,
            minute: 0,
            second: 0,
        },
    };

    pub(crate) fn some(v: YMDHMS) -> Self {
        Self { valid: 1, value: v }
    }
}
