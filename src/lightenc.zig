//! lightenc: small cross-platform encoding conversion for Zig.
//!
//! Design:
//! - Windows: MultiByteToWideChar / WideCharToMultiByte for legacy code pages.
//! - Unix-like: iconv for system-provided conversions.
//! - Manual lightweight paths for UTF-16/UTF-32 byte-order handling.
//! - Public API keeps UTF-8 as the preferred internal representation.

const std = @import("std");
const builtin = @import("builtin");

pub const Allocator = std.mem.Allocator;

/// Public encoding set.
///
/// The enum names are intentionally stable API names. Backend-specific names live in
/// `iconvName`, `windowsCodePage`, and `aliases`.
pub const Encoding = enum {
    ascii,
    utf8,
    utf16le,
    utf16be,
    utf32le,
    utf32be,

    gb2312,
    gbk,
    gb18030,
    shift_jis,
    euc_jp,
    iso_2022_jp,
    big5,
    euc_kr,
    cp949,

    iso_8859_1,
    iso_8859_2,
    iso_8859_5,
    iso_8859_15,

    windows_1250,
    windows_1251,
    windows_1252,
    windows_1253,
    windows_1254,
    windows_1255,
    windows_1256,
    windows_1257,
    windows_1258,

    koi8_r,
    koi8_u,
    mac_roman,
    ibm437,
    ibm850,

    pub fn label(self: Encoding) []const u8 {
        return switch (self) {
            .ascii => "ASCII",
            .utf8 => "UTF-8",
            .utf16le => "UTF-16LE",
            .utf16be => "UTF-16BE",
            .utf32le => "UTF-32LE",
            .utf32be => "UTF-32BE",
            .gb2312 => "GB2312",
            .gbk => "GBK/CP936",
            .gb18030 => "GB18030/CP54936",
            .shift_jis => "Shift_JIS/CP932",
            .euc_jp => "EUC-JP",
            .iso_2022_jp => "ISO-2022-JP",
            .big5 => "Big5/CP950",
            .euc_kr => "EUC-KR",
            .cp949 => "CP949/UHC",
            .iso_8859_1 => "ISO-8859-1",
            .iso_8859_2 => "ISO-8859-2",
            .iso_8859_5 => "ISO-8859-5",
            .iso_8859_15 => "ISO-8859-15",
            .windows_1250 => "Windows-1250",
            .windows_1251 => "Windows-1251",
            .windows_1252 => "Windows-1252",
            .windows_1253 => "Windows-1253",
            .windows_1254 => "Windows-1254",
            .windows_1255 => "Windows-1255",
            .windows_1256 => "Windows-1256",
            .windows_1257 => "Windows-1257",
            .windows_1258 => "Windows-1258",
            .koi8_r => "KOI8-R",
            .koi8_u => "KOI8-U",
            .mac_roman => "MacRoman",
            .ibm437 => "IBM437",
            .ibm850 => "IBM850",
        };
    }

    pub fn aliases(self: Encoding) []const []const u8 {
        return switch (self) {
            .ascii => &.{ "ascii", "us-ascii", "ansi_x3.4-1968", "cp20127" },
            .utf8 => &.{ "utf-8", "utf8", "cp65001" },
            .utf16le => &.{ "utf-16le", "utf16le", "ucs-2le", "cp1200" },
            .utf16be => &.{ "utf-16be", "utf16be", "ucs-2be", "cp1201" },
            .utf32le => &.{ "utf-32le", "utf32le", "ucs-4le" },
            .utf32be => &.{ "utf-32be", "utf32be", "ucs-4be" },
            .gb2312 => &.{ "gb2312", "gb-2312", "euc-cn", "cp20936" },
            .gbk => &.{ "gbk", "cp936", "ms936", "windows-936" },
            .gb18030 => &.{ "gb18030", "cp54936", "windows-54936" },
            .shift_jis => &.{ "shift_jis", "shift-jis", "sjis", "cp932", "windows-31j", "ms932" },
            .euc_jp => &.{ "euc-jp", "eucjp", "cp51932" },
            .iso_2022_jp => &.{ "iso-2022-jp", "iso2022jp", "cp50220" },
            .big5 => &.{ "big5", "big-5", "cp950", "windows-950" },
            .euc_kr => &.{ "euc-kr", "euckr", "ks_c_5601-1987", "cp51949" },
            .cp949 => &.{ "cp949", "windows-949", "uhc", "ks_c_5601-1987-uhc" },
            .iso_8859_1 => &.{ "iso-8859-1", "iso8859-1", "latin1", "latin-1", "cp28591" },
            .iso_8859_2 => &.{ "iso-8859-2", "iso8859-2", "latin2", "latin-2", "cp28592" },
            .iso_8859_5 => &.{ "iso-8859-5", "iso8859-5", "cyrillic", "cp28595" },
            .iso_8859_15 => &.{ "iso-8859-15", "iso8859-15", "latin9", "latin-9", "cp28605" },
            .windows_1250 => &.{ "windows-1250", "cp1250" },
            .windows_1251 => &.{ "windows-1251", "cp1251" },
            .windows_1252 => &.{ "windows-1252", "cp1252" },
            .windows_1253 => &.{ "windows-1253", "cp1253" },
            .windows_1254 => &.{ "windows-1254", "cp1254" },
            .windows_1255 => &.{ "windows-1255", "cp1255" },
            .windows_1256 => &.{ "windows-1256", "cp1256" },
            .windows_1257 => &.{ "windows-1257", "cp1257" },
            .windows_1258 => &.{ "windows-1258", "cp1258" },
            .koi8_r => &.{ "koi8-r", "koi8r", "cp20866" },
            .koi8_u => &.{ "koi8-u", "koi8u", "cp21866" },
            .mac_roman => &.{ "macintosh", "mac", "macroman", "mac-roman", "cp10000" },
            .ibm437 => &.{ "ibm437", "cp437", "437" },
            .ibm850 => &.{ "ibm850", "cp850", "850" },
        };
    }

    pub fn isAsciiSuperset(self: Encoding) bool {
        return switch (self) {
            .ascii,
            .utf8,
            .gb2312,
            .gbk,
            .gb18030,
            .shift_jis,
            .euc_jp,
            .big5,
            .euc_kr,
            .cp949,
            .iso_8859_1,
            .iso_8859_2,
            .iso_8859_5,
            .iso_8859_15,
            .windows_1250,
            .windows_1251,
            .windows_1252,
            .windows_1253,
            .windows_1254,
            .windows_1255,
            .windows_1256,
            .windows_1257,
            .windows_1258,
            .koi8_r,
            .koi8_u,
            .mac_roman,
            .ibm437,
            .ibm850,
            => true,
            .utf16le, .utf16be, .utf32le, .utf32be, .iso_2022_jp => false,
        };
    }

    pub fn isUnicodeFamily(self: Encoding) bool {
        return switch (self) {
            .utf8, .utf16le, .utf16be, .utf32le, .utf32be => true,
            else => false,
        };
    }
};

pub const ErrorPolicy = enum {
    /// Stop on malformed input or unrepresentable output.
    strict,
    /// Ask the backend to substitute where it can. Exact replacement semantics are backend-specific.
    replace,
    /// Best-effort ignore. Portable only when the selected backend supports it.
    ignore,
};

pub const Options = struct {
    policy: ErrorPolicy = .strict,

    /// When true and from == to, validates known self-validating encodings before duplicating.
    validate_identity: bool = false,

    /// Reject UTF-16/UTF-32 byte slices with non-unit-aligned byte lengths.
    reject_misaligned_unicode: bool = true,
};

pub const Error = error{
    UnsupportedTarget,
    UnsupportedEncoding,
    UnsupportedConversion,
    UnsupportedPolicy,
    InvalidSequence,
    IncompleteSequence,
    OutputCannotRepresentInput,
    InputTooLarge,
    SystemFailure,
    OutOfMemory,
};

pub fn parseEncoding(label: []const u8) ?Encoding {
    inline for (std.meta.fields(Encoding)) |field| {
        const enc: Encoding = @as(Encoding, @enumFromInt(field.value));
        for (enc.aliases()) |alias| {
            if (encodingLabelEql(label, alias)) return enc;
        }
    }
    return null;
}

fn encodingLabelEql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub fn convertAlloc(
    allocator: Allocator,
    input: []const u8,
    from: Encoding,
    to: Encoding,
    options: Options,
) Error![]u8 {
    if (input.len == 0) return allocator.alloc(u8, 0) catch return error.OutOfMemory;

    if (from == to) {
        if (options.validate_identity) try validateBytes(input, from, options);
        return allocator.dupe(u8, input) catch return error.OutOfMemory;
    }

    if (from == .ascii and to.isAsciiSuperset()) return duplicateAsciiValidated(allocator, input);
    if (to == .ascii and from.isAsciiSuperset() and isAscii(input)) return allocator.dupe(u8, input) catch return error.OutOfMemory;
    if (from.isAsciiSuperset() and to.isAsciiSuperset() and isAscii(input)) {
        return allocator.dupe(u8, input) catch return error.OutOfMemory;
    }

    return switch (builtin.os.tag) {
        .windows => windows.convertAlloc(allocator, input, from, to, options),
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => iconv_backend.convertAlloc(allocator, input, from, to, options),
        else => error.UnsupportedTarget,
    };
}

pub fn toUtf8Alloc(allocator: Allocator, input: []const u8, from: Encoding, options: Options) Error![]u8 {
    return convertAlloc(allocator, input, from, .utf8, options);
}

pub fn fromUtf8Alloc(allocator: Allocator, input: []const u8, to: Encoding, options: Options) Error![]u8 {
    return convertAlloc(allocator, input, .utf8, to, options);
}

/// Compile-time transcoder. Use this in hot paths to make encoding selection branch-free.
pub fn Transcoder(comptime from: Encoding, comptime to: Encoding) type {
    return struct {
        pub const source_encoding = from;
        pub const target_encoding = to;

        pub fn convertAlloc(allocator: Allocator, input: []const u8, options: Options) Error![]u8 {
            return lightenc.convertAlloc(allocator, input, from, to, options);
        }

        pub fn toUtf8Alloc(allocator: Allocator, input: []const u8, options: Options) Error![]u8 {
            if (to != .utf8) @compileError("Transcoder.toUtf8Alloc requires target encoding .utf8");
            return lightenc.convertAlloc(allocator, input, from, .utf8, options);
        }
    };
}

const lightenc = @This();

pub fn isEncodingSupported(encoding: Encoding) bool {
    return switch (builtin.os.tag) {
        .windows => windows.isEncodingSupported(encoding),
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => iconv_backend.isEncodingSupported(encoding),
        else => false,
    };
}

pub fn isConversionSupported(from: Encoding, to: Encoding) bool {
    if (from == to) return true;
    return switch (builtin.os.tag) {
        .windows => windows.isEncodingSupported(from) and windows.isEncodingSupported(to),
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => iconv_backend.isConversionSupported(from, to),
        else => false,
    };
}

pub fn validateBytes(input: []const u8, encoding: Encoding, options: Options) Error!void {
    switch (encoding) {
        .ascii => if (!isAscii(input)) return error.InvalidSequence,
        .utf8 => if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidSequence,
        .utf16le => {
            const words = try utf16BytesToU16Alloc(std.heap.page_allocator, input, .little, options);
            defer std.heap.page_allocator.free(words);
            try validateUtf16(words);
        },
        .utf16be => {
            const words = try utf16BytesToU16Alloc(std.heap.page_allocator, input, .big, options);
            defer std.heap.page_allocator.free(words);
            try validateUtf16(words);
        },
        .utf32le => try validateUtf32Bytes(input, .little, options),
        .utf32be => try validateUtf32Bytes(input, .big, options),
        else => {
            const tmp = try convertAlloc(std.heap.page_allocator, input, encoding, .utf8, .{ .policy = .strict });
            std.heap.page_allocator.free(tmp);
        },
    }
}

pub fn isAscii(bytes: []const u8) bool {
    for (bytes) |b| if (b >= 0x80) return false;
    return true;
}

fn duplicateAsciiValidated(allocator: Allocator, bytes: []const u8) Error![]u8 {
    if (!isAscii(bytes)) return error.InvalidSequence;
    return allocator.dupe(u8, bytes) catch return error.OutOfMemory;
}

const Endian = enum { little, big };

pub fn utf16leBytesToU16Alloc(allocator: Allocator, bytes: []const u8, options: Options) Error![]u16 {
    return utf16BytesToU16Alloc(allocator, bytes, .little, options);
}

pub fn utf16beBytesToU16Alloc(allocator: Allocator, bytes: []const u8, options: Options) Error![]u16 {
    return utf16BytesToU16Alloc(allocator, bytes, .big, options);
}

fn utf16BytesToU16Alloc(allocator: Allocator, bytes: []const u8, endian: Endian, options: Options) Error![]u16 {
    if (options.reject_misaligned_unicode and bytes.len % 2 != 0) return error.IncompleteSequence;
    if (bytes.len % 2 != 0) return error.IncompleteSequence;

    const out = allocator.alloc(u16, bytes.len / 2) catch return error.OutOfMemory;
    errdefer allocator.free(out);

    for (out, 0..) |*word, i| {
        const j = i * 2;
        word.* = switch (endian) {
            .little => @as(u16, bytes[j]) | (@as(u16, bytes[j + 1]) << 8),
            .big => (@as(u16, bytes[j]) << 8) | @as(u16, bytes[j + 1]),
        };
    }
    return out;
}

pub fn u16ToUtf16leBytesAlloc(allocator: Allocator, words: []const u16) Error![]u8 {
    return u16ToUtf16BytesAlloc(allocator, words, .little);
}

pub fn u16ToUtf16beBytesAlloc(allocator: Allocator, words: []const u16) Error![]u8 {
    return u16ToUtf16BytesAlloc(allocator, words, .big);
}

fn u16ToUtf16BytesAlloc(allocator: Allocator, words: []const u16, endian: Endian) Error![]u8 {
    const out = allocator.alloc(u8, words.len * 2) catch return error.OutOfMemory;
    errdefer allocator.free(out);

    for (words, 0..) |w, i| {
        const j = i * 2;
        switch (endian) {
            .little => {
                out[j] = @as(u8, @truncate(w));
                out[j + 1] = @as(u8, @truncate(w >> 8));
            },
            .big => {
                out[j] = @as(u8, @truncate(w >> 8));
                out[j + 1] = @as(u8, @truncate(w));
            },
        }
    }
    return out;
}

fn utf32BytesToU16Alloc(allocator: Allocator, bytes: []const u8, endian: Endian, options: Options) Error![]u16 {
    if (options.reject_misaligned_unicode and bytes.len % 4 != 0) return error.IncompleteSequence;
    if (bytes.len % 4 != 0) return error.IncompleteSequence;

    const count = bytes.len / 4;
    const out = allocator.alloc(u16, count * 2) catch return error.OutOfMemory;
    errdefer allocator.free(out);

    var out_len: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const j = i * 4;
        const cp: u32 = switch (endian) {
            .little => @as(u32, bytes[j]) |
                (@as(u32, bytes[j + 1]) << 8) |
                (@as(u32, bytes[j + 2]) << 16) |
                (@as(u32, bytes[j + 3]) << 24),
            .big => (@as(u32, bytes[j]) << 24) |
                (@as(u32, bytes[j + 1]) << 16) |
                (@as(u32, bytes[j + 2]) << 8) |
                @as(u32, bytes[j + 3]),
        };
        if (!isValidScalar(cp)) return error.InvalidSequence;
        if (cp <= 0xFFFF) {
            out[out_len] = @as(u16, @intCast(cp));
            out_len += 1;
        } else {
            const v = cp - 0x10000;
            out[out_len] = @as(u16, @intCast(0xD800 + (v >> 10)));
            out[out_len + 1] = @as(u16, @intCast(0xDC00 + (v & 0x3FF)));
            out_len += 2;
        }
    }

    return allocator.realloc(out, out_len) catch return error.OutOfMemory;
}

fn u16ToUtf32BytesAlloc(allocator: Allocator, words: []const u16, endian: Endian) Error![]u8 {
    const out = allocator.alloc(u8, words.len * 4) catch return error.OutOfMemory;
    errdefer allocator.free(out);

    var out_len: usize = 0;
    var i: usize = 0;
    while (i < words.len) {
        const cp = try nextUtf16Scalar(words, &i);
        writeU32(out[out_len .. out_len + 4], cp, endian);
        out_len += 4;
    }

    return allocator.realloc(out, out_len) catch return error.OutOfMemory;
}

fn validateUtf32Bytes(bytes: []const u8, endian: Endian, options: Options) Error!void {
    if (options.reject_misaligned_unicode and bytes.len % 4 != 0) return error.IncompleteSequence;
    if (bytes.len % 4 != 0) return error.IncompleteSequence;

    var i: usize = 0;
    while (i < bytes.len) : (i += 4) {
        const cp: u32 = switch (endian) {
            .little => @as(u32, bytes[i]) |
                (@as(u32, bytes[i + 1]) << 8) |
                (@as(u32, bytes[i + 2]) << 16) |
                (@as(u32, bytes[i + 3]) << 24),
            .big => (@as(u32, bytes[i]) << 24) |
                (@as(u32, bytes[i + 1]) << 16) |
                (@as(u32, bytes[i + 2]) << 8) |
                @as(u32, bytes[i + 3]),
        };
        if (!isValidScalar(cp)) return error.InvalidSequence;
    }
}

fn validateUtf16(words: []const u16) Error!void {
    var i: usize = 0;
    while (i < words.len) {
        _ = try nextUtf16Scalar(words, &i);
    }
}

fn nextUtf16Scalar(words: []const u16, index: *usize) Error!u32 {
    const w1 = words[index.*];
    if (w1 >= 0xD800 and w1 <= 0xDBFF) {
        if (index.* + 1 >= words.len) return error.IncompleteSequence;
        const w2 = words[index.* + 1];
        if (w2 < 0xDC00 or w2 > 0xDFFF) return error.InvalidSequence;
        index.* += 2;
        const high = @as(u32, w1 - 0xD800);
        const low = @as(u32, w2 - 0xDC00);
        return 0x10000 + ((high << 10) | low);
    }
    if (w1 >= 0xDC00 and w1 <= 0xDFFF) return error.InvalidSequence;
    index.* += 1;
    return @as(u32, w1);
}

fn isValidScalar(cp: u32) bool {
    return cp <= 0x10FFFF and !(cp >= 0xD800 and cp <= 0xDFFF);
}

fn writeU32(buf: []u8, cp: u32, endian: Endian) void {
    switch (endian) {
        .little => {
            buf[0] = @as(u8, @truncate(cp));
            buf[1] = @as(u8, @truncate(cp >> 8));
            buf[2] = @as(u8, @truncate(cp >> 16));
            buf[3] = @as(u8, @truncate(cp >> 24));
        },
        .big => {
            buf[0] = @as(u8, @truncate(cp >> 24));
            buf[1] = @as(u8, @truncate(cp >> 16));
            buf[2] = @as(u8, @truncate(cp >> 8));
            buf[3] = @as(u8, @truncate(cp));
        },
    }
}

pub fn assertSupportedAtComptime(comptime from: Encoding, comptime to: Encoding) void {
    if (from == to) return;
    switch (builtin.os.tag) {
        .windows => {},
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => {},
        else => @compileError("lightenc has no backend for this target"),
    }
}

const windows = struct {
    const UINT = u32;
    const DWORD = u32;
    const BOOL = i32;

    const CP_UTF8: UINT = 65001;
    const MB_ERR_INVALID_CHARS: DWORD = 0x00000008;
    const WC_ERR_INVALID_CHARS: DWORD = 0x00000080;
    const WC_NO_BEST_FIT_CHARS: DWORD = 0x00000400;

    extern "kernel32" fn MultiByteToWideChar(
        CodePage: UINT,
        dwFlags: DWORD,
        lpMultiByteStr: [*]const u8,
        cbMultiByte: c_int,
        lpWideCharStr: ?[*]u16,
        cchWideChar: c_int,
    ) callconv(.winapi) c_int;

    extern "kernel32" fn WideCharToMultiByte(
        CodePage: UINT,
        dwFlags: DWORD,
        lpWideCharStr: [*]const u16,
        cchWideChar: c_int,
        lpMultiByteStr: ?[*]u8,
        cbMultiByte: c_int,
        lpDefaultChar: ?[*]const u8,
        lpUsedDefaultChar: ?*BOOL,
    ) callconv(.winapi) c_int;

    extern "kernel32" fn IsValidCodePage(CodePage: UINT) callconv(.winapi) BOOL;

    pub fn isEncodingSupported(enc: Encoding) bool {
        return switch (enc) {
            .utf16le, .utf16be, .utf32le, .utf32be => true,
            else => if (windowsCodePage(enc)) |cp| IsValidCodePage(cp) != 0 else false,
        };
    }

    fn windowsMultiByteFlagsSupported(cp: UINT) bool {
        return switch (cp) {
            // These Windows code pages require dwFlags == 0 for MultiByteToWideChar.
            //
            // 42          = SYMBOL
            // 50220..    = ISO-2022-JP / ISO-2022-KR / ISO-2022-CN variants
            // 57002..    = ISCII variants
            // 65000      = UTF-7
            42,
            50220...50229,
            57002...57011,
            65000,
            => false,

            else => true,
        };
    }

    fn windowsWideFlagsSupported(cp: UINT) bool {
        return switch (cp) {
            // Windows requires dwFlags == 0 for these stateful / special encodings.
            // 54936 = GB18030
            // 50220...50229 = ISO-2022-JP/KR/CN variants
            // 57002...57011 = ISCII variants
            42,
            50220...50229,
            57002...57011,
            65000,
            54936,
            => false,
            else => true,
        };
    }

    fn windowsDefaultCharSupported(cp: UINT) bool {
        return switch (cp) {
            // UTF-7, UTF-8 and GB18030 do not accept lpDefaultChar/lpUsedDefaultChar.
            65000, 65001, 54936 => false,
            else => true,
        };
    }

    fn windowsCodePage(enc: Encoding) ?UINT {
        return switch (enc) {
            .ascii => 20127,
            .utf8 => CP_UTF8,
            .utf16le, .utf16be, .utf32le, .utf32be => null,
            .gb2312 => 936,
            .gbk => 936,
            .gb18030 => 54936,
            .shift_jis => 932,
            .euc_jp => 51932,
            .iso_2022_jp => 50220,
            .big5 => 950,
            .euc_kr => 51949,
            .cp949 => 949,
            .iso_8859_1 => 28591,
            .iso_8859_2 => 28592,
            .iso_8859_5 => 28595,
            .iso_8859_15 => 28605,
            .windows_1250 => 1250,
            .windows_1251 => 1251,
            .windows_1252 => 1252,
            .windows_1253 => 1253,
            .windows_1254 => 1254,
            .windows_1255 => 1255,
            .windows_1256 => 1256,
            .windows_1257 => 1257,
            .windows_1258 => 1258,
            .koi8_r => 20866,
            .koi8_u => 21866,
            .mac_roman => 10000,
            .ibm437 => 437,
            .ibm850 => 850,
        };
    }

    pub fn convertAlloc(allocator: Allocator, input: []const u8, from: Encoding, to: Encoding, options: Options) Error![]u8 {
        const wide = try toWideAlloc(allocator, input, from, options);
        defer allocator.free(wide);
        return fromWideAlloc(allocator, wide, to, options);
    }

    fn checkedCLen(len: usize) Error!c_int {
        if (len > @as(usize, @intCast(std.math.maxInt(c_int)))) return error.InputTooLarge;
        return @as(c_int, @intCast(len));
    }

    fn toWideAlloc(allocator: Allocator, input: []const u8, from: Encoding, options: Options) Error![]u16 {
        return switch (from) {
            .utf16le => blk: {
                const words = try utf16leBytesToU16Alloc(allocator, input, options);
                errdefer allocator.free(words);
                try validateUtf16(words);
                break :blk words;
            },
            .utf16be => blk: {
                const words = try utf16beBytesToU16Alloc(allocator, input, options);
                errdefer allocator.free(words);
                try validateUtf16(words);
                break :blk words;
            },
            .utf32le => utf32BytesToU16Alloc(allocator, input, .little, options),
            .utf32be => utf32BytesToU16Alloc(allocator, input, .big, options),
            else => toWideViaCodePageAlloc(allocator, input, from, options),
        };
    }

    fn toWideViaCodePageAlloc(allocator: Allocator, input: []const u8, from: Encoding, options: Options) Error![]u16 {
        const cp = windowsCodePage(from) orelse return error.UnsupportedEncoding;
        if (IsValidCodePage(cp) == 0) return error.UnsupportedEncoding;

        const flags: DWORD = switch (options.policy) {
            .strict => MB_ERR_INVALID_CHARS,
            .replace => 0,
            .ignore => return error.UnsupportedPolicy,
        };

        const in_len = try checkedCLen(input.len);
        const needed = MultiByteToWideChar(cp, flags, input.ptr, in_len, null, 0);
        if (needed <= 0) return error.InvalidSequence;

        const out = allocator.alloc(u16, @as(usize, @intCast(needed))) catch return error.OutOfMemory;
        errdefer allocator.free(out);

        const written = MultiByteToWideChar(cp, flags, input.ptr, in_len, out.ptr, needed);
        if (written != needed) return error.SystemFailure;
        return out;
    }

    fn fromWideAlloc(allocator: Allocator, wide: []const u16, to: Encoding, options: Options) Error![]u8 {
        try validateUtf16(wide);
        return switch (to) {
            .utf16le => u16ToUtf16leBytesAlloc(allocator, wide),
            .utf16be => u16ToUtf16beBytesAlloc(allocator, wide),
            .utf32le => u16ToUtf32BytesAlloc(allocator, wide, .little),
            .utf32be => u16ToUtf32BytesAlloc(allocator, wide, .big),
            else => fromWideViaCodePageAlloc(allocator, wide, to, options),
        };
    }

    fn fromWideViaCodePageAlloc(allocator: Allocator, wide: []const u16, to: Encoding, options: Options) Error![]u8 {
        const cp = windowsCodePage(to) orelse return error.UnsupportedEncoding;
        if (IsValidCodePage(cp) == 0) return error.UnsupportedEncoding;

        const wide_len = try checkedCLen(wide.len);

        var default_char: [1]u8 = .{'?'};
        var used_default: BOOL = 0;

        var flags: DWORD = 0;
        var default_ptr: ?[*]const u8 = null;
        var used_ptr: ?*BOOL = null;

        const can_use_wide_flags = windowsWideFlagsSupported(cp);
        const can_use_default_char = windowsDefaultCharSupported(cp);

        switch (options.policy) {
            .strict => {
                if (to == .utf8 and can_use_wide_flags) {
                    flags = WC_ERR_INVALID_CHARS;
                } else if (can_use_wide_flags) {
                    flags = WC_NO_BEST_FIT_CHARS;

                    if (can_use_default_char) {
                        default_ptr = &default_char;
                        used_ptr = &used_default;
                    }
                } else {
                    // Some Windows code pages, notably GB18030 / CP54936,
                    // require dwFlags == 0 and default-char pointers == NULL.
                    //
                    // Strict unrepresentable-character detection is weaker here.
                    flags = 0;
                }
            },
            .replace => {
                if (can_use_default_char) {
                    default_ptr = &default_char;
                }
            },
            .ignore => return error.UnsupportedPolicy,
        }

        const needed = WideCharToMultiByte(cp, flags, wide.ptr, wide_len, null, 0, default_ptr, used_ptr);
        if (needed <= 0) return error.OutputCannotRepresentInput;

        const out = allocator.alloc(u8, @as(usize, @intCast(needed))) catch return error.OutOfMemory;
        errdefer allocator.free(out);

        used_default = 0;
        const written = WideCharToMultiByte(cp, flags, wide.ptr, wide_len, out.ptr, needed, default_ptr, used_ptr);
        if (written != needed) return error.SystemFailure;
        if (options.policy == .strict and used_default != 0) return error.OutputCannotRepresentInput;
        return out;
    }
};

const iconv_backend = struct {
    const Self = @This();
    const IconvDescriptor = *anyopaque;
    const ICONV_FAIL: usize = std.math.maxInt(usize);

    extern fn iconv_open(tocode: [*:0]const u8, fromcode: [*:0]const u8) ?IconvDescriptor;
    extern fn iconv_close(cd: IconvDescriptor) c_int;
    extern fn iconv(
        cd: IconvDescriptor,
        inbuf: ?*?[*]u8,
        inbytesleft: ?*usize,
        outbuf: ?*?[*]u8,
        outbytesleft: ?*usize,
    ) usize;

    pub fn isEncodingSupported(enc: Encoding) bool {
        if (enc == .utf8) return true;
        return Self.isConversionSupported(enc, .utf8) or Self.isConversionSupported(.utf8, enc);
    }

    pub fn isConversionSupported(from: Encoding, to: Encoding) bool {
        if (from == to) return true;
        const cd = iconv_open(iconvName(to).ptr, iconvName(from).ptr) orelse return false;
        _ = iconv_close(cd);
        return true;
    }

    pub fn convertAlloc(allocator: Allocator, input: []const u8, from: Encoding, to: Encoding, options: Options) Error![]u8 {
        const from_name = iconvName(from);
        const to_name = try iconvTargetName(to, options.policy);

        const cd = iconv_open(to_name.ptr, from_name.ptr) orelse return error.UnsupportedConversion;
        defer _ = iconv_close(cd);

        return runIconvAlloc(allocator, cd, input);
    }

    fn iconvName(enc: Encoding) [:0]const u8 {
        return switch (enc) {
            .ascii => "ASCII",
            .utf8 => "UTF-8",
            .utf16le => "UTF-16LE",
            .utf16be => "UTF-16BE",
            .utf32le => "UTF-32LE",
            .utf32be => "UTF-32BE",
            .gb2312 => "GB2312",
            .gbk => "GBK",
            .gb18030 => "GB18030",
            .shift_jis => "CP932",
            .euc_jp => "EUC-JP",
            .iso_2022_jp => "ISO-2022-JP",
            .big5 => "BIG5",
            .euc_kr => "EUC-KR",
            .cp949 => "CP949",
            .iso_8859_1 => "ISO-8859-1",
            .iso_8859_2 => "ISO-8859-2",
            .iso_8859_5 => "ISO-8859-5",
            .iso_8859_15 => "ISO-8859-15",
            .windows_1250 => "WINDOWS-1250",
            .windows_1251 => "WINDOWS-1251",
            .windows_1252 => "WINDOWS-1252",
            .windows_1253 => "WINDOWS-1253",
            .windows_1254 => "WINDOWS-1254",
            .windows_1255 => "WINDOWS-1255",
            .windows_1256 => "WINDOWS-1256",
            .windows_1257 => "WINDOWS-1257",
            .windows_1258 => "WINDOWS-1258",
            .koi8_r => "KOI8-R",
            .koi8_u => "KOI8-U",
            .mac_roman => "MACINTOSH",
            .ibm437 => "IBM437",
            .ibm850 => "IBM850",
        };
    }

    fn iconvTargetName(enc: Encoding, policy: ErrorPolicy) Error![:0]const u8 {
        return switch (policy) {
            .strict => iconvName(enc),
            .replace => switch (enc) {
                .ascii => "ASCII//TRANSLIT",
                .utf8 => "UTF-8//TRANSLIT",
                .utf16le => "UTF-16LE//TRANSLIT",
                .utf16be => "UTF-16BE//TRANSLIT",
                .utf32le => "UTF-32LE//TRANSLIT",
                .utf32be => "UTF-32BE//TRANSLIT",
                .gb2312 => "GB2312//TRANSLIT",
                .gbk => "GBK//TRANSLIT",
                .gb18030 => "GB18030//TRANSLIT",
                .shift_jis => "CP932//TRANSLIT",
                .euc_jp => "EUC-JP//TRANSLIT",
                .iso_2022_jp => "ISO-2022-JP//TRANSLIT",
                .big5 => "BIG5//TRANSLIT",
                .euc_kr => "EUC-KR//TRANSLIT",
                .cp949 => "CP949//TRANSLIT",
                .iso_8859_1 => "ISO-8859-1//TRANSLIT",
                .iso_8859_2 => "ISO-8859-2//TRANSLIT",
                .iso_8859_5 => "ISO-8859-5//TRANSLIT",
                .iso_8859_15 => "ISO-8859-15//TRANSLIT",
                .windows_1250 => "WINDOWS-1250//TRANSLIT",
                .windows_1251 => "WINDOWS-1251//TRANSLIT",
                .windows_1252 => "WINDOWS-1252//TRANSLIT",
                .windows_1253 => "WINDOWS-1253//TRANSLIT",
                .windows_1254 => "WINDOWS-1254//TRANSLIT",
                .windows_1255 => "WINDOWS-1255//TRANSLIT",
                .windows_1256 => "WINDOWS-1256//TRANSLIT",
                .windows_1257 => "WINDOWS-1257//TRANSLIT",
                .windows_1258 => "WINDOWS-1258//TRANSLIT",
                .koi8_r => "KOI8-R//TRANSLIT",
                .koi8_u => "KOI8-U//TRANSLIT",
                .mac_roman => "MACINTOSH//TRANSLIT",
                .ibm437 => "IBM437//TRANSLIT",
                .ibm850 => "IBM850//TRANSLIT",
            },
            .ignore => switch (enc) {
                .ascii => "ASCII//IGNORE",
                .utf8 => "UTF-8//IGNORE",
                .utf16le => "UTF-16LE//IGNORE",
                .utf16be => "UTF-16BE//IGNORE",
                .utf32le => "UTF-32LE//IGNORE",
                .utf32be => "UTF-32BE//IGNORE",
                .gb2312 => "GB2312//IGNORE",
                .gbk => "GBK//IGNORE",
                .gb18030 => "GB18030//IGNORE",
                .shift_jis => "CP932//IGNORE",
                .euc_jp => "EUC-JP//IGNORE",
                .iso_2022_jp => "ISO-2022-JP//IGNORE",
                .big5 => "BIG5//IGNORE",
                .euc_kr => "EUC-KR//IGNORE",
                .cp949 => "CP949//IGNORE",
                .iso_8859_1 => "ISO-8859-1//IGNORE",
                .iso_8859_2 => "ISO-8859-2//IGNORE",
                .iso_8859_5 => "ISO-8859-5//IGNORE",
                .iso_8859_15 => "ISO-8859-15//IGNORE",
                .windows_1250 => "WINDOWS-1250//IGNORE",
                .windows_1251 => "WINDOWS-1251//IGNORE",
                .windows_1252 => "WINDOWS-1252//IGNORE",
                .windows_1253 => "WINDOWS-1253//IGNORE",
                .windows_1254 => "WINDOWS-1254//IGNORE",
                .windows_1255 => "WINDOWS-1255//IGNORE",
                .windows_1256 => "WINDOWS-1256//IGNORE",
                .windows_1257 => "WINDOWS-1257//IGNORE",
                .windows_1258 => "WINDOWS-1258//IGNORE",
                .koi8_r => "KOI8-R//IGNORE",
                .koi8_u => "KOI8-U//IGNORE",
                .mac_roman => "MACINTOSH//IGNORE",
                .ibm437 => "IBM437//IGNORE",
                .ibm850 => "IBM850//IGNORE",
            },
        };
    }

    fn runIconvAlloc(allocator: Allocator, cd: IconvDescriptor, input: []const u8) Error![]u8 {
        var cap = try initialOutputCapacity(input.len);
        var out = allocator.alloc(u8, cap) catch return error.OutOfMemory;
        errdefer allocator.free(out);

        var in_ptr: ?[*]u8 = @constCast(input.ptr);
        var in_left: usize = input.len;
        var out_len: usize = 0;

        while (in_left > 0) {
            var out_ptr: ?[*]u8 = out.ptr + out_len;
            var out_left: usize = out.len - out_len;

            if (out_left == 0) {
                out = try grow(allocator, out, &cap);
                continue;
            }

            const before_in = in_left;
            const rc = iconv(cd, &in_ptr, &in_left, &out_ptr, &out_left);
            out_len = out.len - out_left;
            if (rc != ICONV_FAIL) break;

            if (out_left == 0 or in_left == before_in) {
                out = try grow(allocator, out, &cap);
                if (cap > std.math.maxInt(usize) / 2) return error.OutOfMemory;
                if (out_left == 0) continue;
            }

            // Without depending on errno, a failed conversion with remaining output space is
            // treated as malformed or incomplete input. This keeps the wrapper libc-agnostic.
            return error.InvalidSequence;
        }

        // Flush stateful encoders.
        while (true) {
            var out_ptr: ?[*]u8 = out.ptr + out_len;
            var out_left: usize = out.len - out_len;
            if (out_left == 0) {
                out = try grow(allocator, out, &cap);
                continue;
            }

            const rc = iconv(cd, null, null, &out_ptr, &out_left);
            out_len = out.len - out_left;
            if (rc != ICONV_FAIL) break;
            if (out_left == 0) {
                out = try grow(allocator, out, &cap);
                continue;
            }
            return error.SystemFailure;
        }

        return allocator.realloc(out, out_len) catch return error.OutOfMemory;
    }

    fn initialOutputCapacity(input_len: usize) Error!usize {
        if (input_len < 64) return 128;
        if (input_len > (std.math.maxInt(usize) - 16) / 4) return error.InputTooLarge;
        return input_len * 4 + 16;
    }

    fn grow(allocator: Allocator, old: []u8, cap: *usize) Error![]u8 {
        if (cap.* > std.math.maxInt(usize) / 2) return error.OutOfMemory;
        var new_cap = cap.* * 2;
        if (new_cap < 128) new_cap = 128;
        const resized = allocator.realloc(old, new_cap) catch return error.OutOfMemory;
        cap.* = new_cap;
        return resized;
    }
};

test "parse common encoding aliases" {
    try std.testing.expectEqual(Encoding.utf8, parseEncoding("utf-8").?);
    try std.testing.expectEqual(Encoding.gbk, parseEncoding("cp936").?);
    try std.testing.expectEqual(Encoding.shift_jis, parseEncoding("windows-31j").?);
    try std.testing.expectEqual(Encoding.windows_1252, parseEncoding("WINDOWS-1252").?);
    try std.testing.expectEqual(@as(?Encoding, null), parseEncoding("not-an-encoding"));
}

test "ascii fast path preserves bytes across ascii-compatible encodings" {
    const allocator = std.testing.allocator;
    const out = try convertAlloc(allocator, "hello", .utf8, .gbk, .{});
    defer allocator.free(out);
    try std.testing.expectEqualStrings("hello", out);
}

test "ascii source rejects non-ascii bytes" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidSequence, convertAlloc(allocator, &.{0x80}, .ascii, .utf8, .{}));
}

test "utf16 byte helpers roundtrip little and big endian" {
    const allocator = std.testing.allocator;
    const words = [_]u16{ 'A', 0x4E2D, 0xD83D, 0xDE00 };

    const le = try u16ToUtf16leBytesAlloc(allocator, &words);
    defer allocator.free(le);
    const le_words = try utf16leBytesToU16Alloc(allocator, le, .{});
    defer allocator.free(le_words);
    try std.testing.expectEqualSlices(u16, &words, le_words);

    const be = try u16ToUtf16beBytesAlloc(allocator, &words);
    defer allocator.free(be);
    const be_words = try utf16beBytesToU16Alloc(allocator, be, .{});
    defer allocator.free(be_words);
    try std.testing.expectEqualSlices(u16, &words, be_words);
}

test "utf32 manual path roundtrips through UTF-16 words" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        0x41, 0x00, 0x00, 0x00,
        0x00, 0x4e, 0x00, 0x00,
        0x00, 0xf6, 0x01, 0x00,
    };
    const words = try utf32BytesToU16Alloc(allocator, &bytes, .little, .{});
    defer allocator.free(words);
    const out = try u16ToUtf32BytesAlloc(allocator, words, .little);
    defer allocator.free(out);
    try std.testing.expectEqualSlices(u8, &bytes, out);
}
