const std = @import("std");
const enc = @import("lightenc");
const opts = @import("test_options");

const Fixture = struct {
    name: []const u8,
    encoding: enc.Encoding,
    encoded: []const u8,
    utf8: []const u8,
    extended: bool = false,
    roundtrip_exact: bool = true,
};

const fixtures = [_]Fixture{
    .{
        .name = "utf16le",
        .encoding = .utf16le,
        .encoded = &.{ 0x41, 0x00, 0x2d, 0x4e, 0x3d, 0xd8, 0x00, 0xde },
        .utf8 = "A中😀",
    },
    .{
        .name = "utf16be",
        .encoding = .utf16be,
        .encoded = &.{ 0x00, 0x41, 0x4e, 0x2d, 0xd8, 0x3d, 0xde, 0x00 },
        .utf8 = "A中😀",
    },
    .{
        .name = "utf32le",
        .encoding = .utf32le,
        .encoded = &.{ 0x41, 0x00, 0x00, 0x00, 0x2d, 0x4e, 0x00, 0x00, 0x00, 0xf6, 0x01, 0x00 },
        .utf8 = "A中😀",
    },
    .{
        .name = "utf32be",
        .encoding = .utf32be,
        .encoded = &.{ 0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x4e, 0x2d, 0x00, 0x01, 0xf6, 0x00 },
        .utf8 = "A中😀",
    },
    .{
        .name = "latin1",
        .encoding = .iso_8859_1,
        .encoded = &.{ 'c', 'a', 'f', 0xe9 },
        .utf8 = "café",
    },
    .{
        .name = "windows-1252-smart-quotes",
        .encoding = .windows_1252,
        .encoded = &.{ 0x93, 'O', 'K', 0x94 },
        .utf8 = "“OK”",
    },
    .{
        .name = "gbk",
        .encoding = .gbk,
        .encoded = &.{ 0xd6, 0xd0, 0xce, 0xc4 },
        .utf8 = "中文",
    },
    .{
        .name = "gb18030-as-gbk-subset",
        .encoding = .gb18030,
        .encoded = &.{ 0xd6, 0xd0, 0xce, 0xc4 },
        .utf8 = "中文",
    },
    .{
        .name = "shift-jis-cp932",
        .encoding = .shift_jis,
        .encoded = &.{ 0x93, 0xfa, 0x96, 0x7b },
        .utf8 = "日本",
    },
    .{
        .name = "big5",
        .encoding = .big5,
        .encoded = &.{ 0xa4, 0xa4, 0xa4, 0xe5 },
        .utf8 = "中文",
    },
    .{
        .name = "euc-jp",
        .encoding = .euc_jp,
        .encoded = &.{ 0xc6, 0xfc, 0xcb, 0xdc },
        .utf8 = "日本",
        .extended = true,
    },
    .{
        .name = "iso-2022-jp",
        .encoding = .iso_2022_jp,
        .encoded = &.{ 0x1b, 0x24, 0x42, 0x46, 0x7c, 0x4b, 0x5c, 0x1b, 0x28, 0x42 },
        .utf8 = "日本",
        .extended = true,
        .roundtrip_exact = false,
    },
    .{
        .name = "euc-kr",
        .encoding = .euc_kr,
        .encoded = &.{ 0xc7, 0xd1, 0xb1, 0xdb },
        .utf8 = "한글",
        .extended = true,
    },
    .{
        .name = "cp949",
        .encoding = .cp949,
        .encoded = &.{ 0xc7, 0xd1, 0xb1, 0xdb },
        .utf8 = "한글",
        .extended = true,
    },
    .{
        .name = "cp1251",
        .encoding = .windows_1251,
        .encoded = &.{ 0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2 },
        .utf8 = "Привет",
        .extended = true,
    },
    .{
        .name = "ibm437",
        .encoding = .ibm437,
        .encoded = &.{ 0x82 },
        .utf8 = "é",
        .extended = true,
    },
    .{
        .name = "mac-roman",
        .encoding = .mac_roman,
        .encoded = &.{ 0x8e },
        .utf8 = "é",
        .extended = true,
    },
};

test "backend support probes do not crash" {
    _ = enc.isEncodingSupported(.utf8);
    _ = enc.isConversionSupported(.utf8, .utf16le);
    _ = enc.isConversionSupported(.gbk, .utf8);
}

test "backend fixture matrix: encoded bytes to UTF-8" {
    const allocator = std.testing.allocator;

    var ran_any = false;
    for (fixtures) |fixture| {
        if (fixture.extended and !opts.extended) continue;

        if (!enc.isConversionSupported(fixture.encoding, .utf8)) {
            if (opts.strict_backend) {
                std.debug.print("unsupported fixture conversion {s} -> UTF-8\n", .{fixture.name});
                try std.testing.expect(false);
            }
            continue;
        }

        ran_any = true;
        const out = try enc.toUtf8Alloc(allocator, fixture.encoded, fixture.encoding, .{ .policy = .strict });
        defer allocator.free(out);
        try std.testing.expectEqualStrings(fixture.utf8, out);
    }

    try std.testing.expect(ran_any);
}

test "backend fixture matrix: exact UTF-8 roundtrip where canonical" {
    const allocator = std.testing.allocator;

    var ran_any = false;
    for (fixtures) |fixture| {
        if (fixture.extended and !opts.extended) continue;
        if (!fixture.roundtrip_exact) continue;

        if (!enc.isConversionSupported(.utf8, fixture.encoding) or !enc.isConversionSupported(fixture.encoding, .utf8)) {
            if (opts.strict_backend) {
                std.debug.print("unsupported roundtrip fixture UTF-8 <-> {s}\n", .{fixture.name});
                try std.testing.expect(false);
            }
            continue;
        }

        ran_any = true;
        const encoded = try enc.fromUtf8Alloc(allocator, fixture.utf8, fixture.encoding, .{ .policy = .strict });
        defer allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, fixture.encoded, encoded);

        const utf8 = try enc.toUtf8Alloc(allocator, encoded, fixture.encoding, .{ .policy = .strict });
        defer allocator.free(utf8);
        try std.testing.expectEqualStrings(fixture.utf8, utf8);
    }

    try std.testing.expect(ran_any);
}
