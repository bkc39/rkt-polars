use crate::prelude::*;
use polars::export::arrow::array::Array;
use polars::export::arrow::bitmap::Bitmap;
use polars::export::num::AsPrimitive;

pub const COPY_BAD_ARGUMENTS: i64 = -1;
pub const COPY_WRONG_DTYPE: i64 = -2;

fn row_range(s: &Series, start: usize, count: usize) -> Option<Series> {
    let end = start.checked_add(count)?;
    (end <= s.len()).then(|| s.slice(start as i64, count))
}

fn room_for(
    count: usize,
    dst: *const u8,
    dst_len: usize,
    valid: *const u8,
    valid_len: usize,
) -> bool {
    count <= dst_len
        && (count == 0 || !dst.is_null())
        && (valid.is_null() || count <= valid_len)
}

unsafe fn write_bits(bits: Option<&Bitmap>, out: *mut u8, len: usize) {
    let out = std::slice::from_raw_parts_mut(out, len);
    match bits {
        Some(bits) => {
            for (slot, bit) in out.iter_mut().zip(bits.iter()) {
                *slot = bit as u8;
            }
        }
        None => out.fill(1),
    }
}

unsafe fn copy_physical<T: PolarsNumericType>(
    ca: &ChunkedArray<T>,
    dst: *mut T::Native,
    valid: *mut u8,
) -> i64 {
    let mut row = 0;
    for arr in ca.downcast_iter() {
        let values = arr.values().as_slice();
        ptr::copy_nonoverlapping(values.as_ptr(), dst.add(row), values.len());
        if !valid.is_null() {
            write_bits(arr.validity(), valid.add(row), values.len());
        }
        row += values.len();
    }
    ca.null_count() as i64
}

macro_rules! series_copy_physical {
    ($name:ident, $native:ty, $as_chunked:ident) => {
        #[no_mangle]
        pub extern "C" fn $name(
            s_ptr: *const Series,
            start: usize,
            count: usize,
            dst: *mut $native,
            dst_len: usize,
            valid: *mut u8,
            valid_len: usize,
        ) -> i64 {
            let Some(s) = (unsafe { s_ptr.as_ref() }) else {
                return COPY_BAD_ARGUMENTS;
            };
            let physical = s.to_physical_repr();
            if physical.$as_chunked().is_err() {
                return COPY_WRONG_DTYPE;
            }
            let Some(rows) = row_range(&physical, start, count) else {
                return COPY_BAD_ARGUMENTS;
            };
            if !room_for(count, dst as *const u8, dst_len, valid, valid_len) {
                return COPY_BAD_ARGUMENTS;
            }
            match rows.$as_chunked() {
                Ok(ca) if count > 0 => unsafe { copy_physical(ca, dst, valid) },
                _ => 0,
            }
        }
    };
}

series_copy_physical!(series_copy_i8, i8, i8);
series_copy_physical!(series_copy_i16, i16, i16);
series_copy_physical!(series_copy_i32, i32, i32);
series_copy_physical!(series_copy_i64, i64, i64);
series_copy_physical!(series_copy_u8, u8, u8);
series_copy_physical!(series_copy_u16, u16, u16);
series_copy_physical!(series_copy_u32, u32, u32);
series_copy_physical!(series_copy_u64, u64, u64);
series_copy_physical!(series_copy_f32, f32, f32);
series_copy_physical!(series_copy_f64, f64, f64);

#[no_mangle]
pub extern "C" fn series_copy_bool(
    s_ptr: *const Series,
    start: usize,
    count: usize,
    dst: *mut u8,
    dst_len: usize,
    valid: *mut u8,
    valid_len: usize,
) -> i64 {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return COPY_BAD_ARGUMENTS;
    };
    if s.bool().is_err() {
        return COPY_WRONG_DTYPE;
    }
    let Some(rows) = row_range(s, start, count) else {
        return COPY_BAD_ARGUMENTS;
    };
    if !room_for(count, dst, dst_len, valid, valid_len) {
        return COPY_BAD_ARGUMENTS;
    }
    let Ok(ca) = rows.bool() else {
        return COPY_WRONG_DTYPE;
    };
    if count == 0 {
        return 0;
    }
    let mut row = 0;
    for arr in ca.downcast_iter() {
        unsafe {
            write_bits(Some(arr.values()), dst.add(row), arr.len());
            if !valid.is_null() {
                write_bits(arr.validity(), valid.add(row), arr.len());
            }
        }
        row += arr.len();
    }
    ca.null_count() as i64
}

fn str_byte_len(ca: &StringChunked) -> usize {
    ca.into_iter().flatten().map(str::len).sum()
}

#[no_mangle]
pub extern "C" fn series_str_byte_len(
    s_ptr: *const Series,
    start: usize,
    count: usize,
) -> i64 {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return COPY_BAD_ARGUMENTS;
    };
    if s.str().is_err() {
        return COPY_WRONG_DTYPE;
    }
    let Some(rows) = row_range(s, start, count) else {
        return COPY_BAD_ARGUMENTS;
    };
    match rows.str() {
        Ok(ca) => str_byte_len(ca) as i64,
        Err(_) => COPY_WRONG_DTYPE,
    }
}

#[no_mangle]
pub extern "C" fn series_copy_str(
    s_ptr: *const Series,
    start: usize,
    count: usize,
    buf: *mut u8,
    buf_len: usize,
    offsets: *mut i64,
    offsets_len: usize,
    valid: *mut u8,
    valid_len: usize,
) -> i64 {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return COPY_BAD_ARGUMENTS;
    };
    if s.str().is_err() {
        return COPY_WRONG_DTYPE;
    }
    let Some(rows) = row_range(s, start, count) else {
        return COPY_BAD_ARGUMENTS;
    };
    let Ok(ca) = rows.str() else {
        return COPY_WRONG_DTYPE;
    };
    let total = str_byte_len(ca);
    if offsets.is_null()
        || offsets_len <= count
        || total > buf_len
        || (buf.is_null() && total > 0)
        || !(valid.is_null() || count <= valid_len)
    {
        return COPY_BAD_ARGUMENTS;
    }
    let offsets = unsafe { std::slice::from_raw_parts_mut(offsets, count + 1) };
    let mut end = 0;
    offsets[0] = 0;
    for (row, value) in ca.into_iter().enumerate() {
        if let Some(text) = value.filter(|text| !text.is_empty()) {
            unsafe {
                ptr::copy_nonoverlapping(
                    text.as_ptr(),
                    buf.add(end),
                    text.len(),
                );
            }
            end += text.len();
        }
        if !valid.is_null() {
            unsafe { *valid.add(row) = value.is_some() as u8 };
        }
        offsets[row + 1] = end as i64;
    }
    ca.null_count() as i64
}

struct Strided {
    dst: *mut f64,
    offset: usize,
    stride: usize,
    null_value: f64,
}

impl Strided {
    unsafe fn put(&self, row: usize, value: f64) {
        *self.dst.add(self.offset + row * self.stride) = value;
    }
}

unsafe fn copy_as_f64<T>(ca: &ChunkedArray<T>, out: &Strided)
where
    T: PolarsNumericType,
    T::Native: AsPrimitive<f64>,
{
    let mut row = 0;
    for arr in ca.downcast_iter() {
        let values = arr.values().as_slice();
        if out.stride == 1 {
            let dst = std::slice::from_raw_parts_mut(
                out.dst.add(out.offset + row),
                values.len(),
            );
            for (slot, v) in dst.iter_mut().zip(values) {
                *slot = v.as_();
            }
        } else {
            for (k, v) in values.iter().enumerate() {
                out.put(row + k, v.as_());
            }
        }
        if let Some(bits) = arr.validity().filter(|_| arr.null_count() > 0) {
            for (k, ok) in bits.iter().enumerate() {
                if !ok {
                    out.put(row + k, out.null_value);
                }
            }
        }
        row += values.len();
    }
}

unsafe fn copy_bool_as_f64(ca: &BooleanChunked, out: &Strided) {
    for (row, value) in ca.into_iter().enumerate() {
        out.put(row, value.map_or(out.null_value, f64::from));
    }
}

unsafe fn copy_null_as_f64(len: usize, out: &Strided) {
    for row in 0..len {
        out.put(row, out.null_value);
    }
}

fn first_null(s: &Series) -> usize {
    if s.dtype() == &DataType::Null {
        return 0;
    }
    let mut row = 0;
    for arr in s.chunks() {
        let null = arr
            .validity()
            .and_then(|bits| bits.iter().position(|ok| !ok));
        if let Some(k) = null {
            return row + k;
        }
        row += arr.len();
    }
    row
}

fn f64_convertible(dtype: &DataType) -> bool {
    dtype.is_numeric() || matches!(dtype, DataType::Boolean | DataType::Null)
}

#[no_mangle]
pub extern "C" fn series_copy_as_f64(
    s_ptr: *const Series,
    dst: *mut f64,
    dst_len: usize,
    offset: usize,
    stride: usize,
    null_value: f64,
) -> i64 {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return COPY_BAD_ARGUMENTS;
    };
    if !f64_convertible(s.dtype()) {
        return COPY_WRONG_DTYPE;
    }
    let n = s.len();
    let last = n
        .checked_sub(1)
        .map(|rows| rows.checked_mul(stride)?.checked_add(offset));
    let fits = match last {
        None => true,
        Some(Some(last)) => !dst.is_null() && last < dst_len,
        Some(None) => false,
    };
    if stride == 0 || !fits {
        return COPY_BAD_ARGUMENTS;
    }
    let out = Strided {
        dst,
        offset,
        stride,
        null_value,
    };
    let copied = unsafe {
        match s.dtype() {
            DataType::Int8 => s.i8().map(|ca| copy_as_f64(ca, &out)),
            DataType::Int16 => s.i16().map(|ca| copy_as_f64(ca, &out)),
            DataType::Int32 => s.i32().map(|ca| copy_as_f64(ca, &out)),
            DataType::Int64 => s.i64().map(|ca| copy_as_f64(ca, &out)),
            DataType::UInt8 => s.u8().map(|ca| copy_as_f64(ca, &out)),
            DataType::UInt16 => s.u16().map(|ca| copy_as_f64(ca, &out)),
            DataType::UInt32 => s.u32().map(|ca| copy_as_f64(ca, &out)),
            DataType::UInt64 => s.u64().map(|ca| copy_as_f64(ca, &out)),
            DataType::Float32 => s.f32().map(|ca| copy_as_f64(ca, &out)),
            DataType::Float64 => s.f64().map(|ca| copy_as_f64(ca, &out)),
            DataType::Boolean => s.bool().map(|ca| copy_bool_as_f64(ca, &out)),
            DataType::Null => {
                copy_null_as_f64(n, &out);
                Ok(())
            }
            _ => return COPY_WRONG_DTYPE,
        }
    };
    match copied {
        Ok(()) => first_null(s) as i64,
        Err(_) => COPY_WRONG_DTYPE,
    }
}
