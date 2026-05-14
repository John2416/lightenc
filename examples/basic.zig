const std = @import("std");
const enc = @import("lightenc");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source_encoding = enc.parseEncoding("gbk") orelse return error.UnknownEncoding;
    const gbk_bytes = [_]u8{ 0xd6, 0xd0, 0xce, 0xc4 }; // "中文" in GBK/CP936

    const utf8 = try enc.toUtf8Alloc(allocator, &gbk_bytes, source_encoding, .{});
    defer allocator.free(utf8);

    try std.io.getStdOut().writer().print("GBK -> UTF-8: {s}\n", .{utf8});

    const sjis = try enc.fromUtf8Alloc(allocator, "日本", .shift_jis, .{ .policy = .strict });
    defer allocator.free(sjis);

    try std.io.getStdOut().writer().print("UTF-8 -> CP932 bytes: ", .{});
    for (sjis) |b| try std.io.getStdOut().writer().print("{X:0>2} ", .{b});
    try std.io.getStdOut().writer().print("\n", .{});
}
