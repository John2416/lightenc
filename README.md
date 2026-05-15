# lightenc

`lightenc` is a small cross-platform encoding conversion library for Zig.

It uses native system backends instead of bundling large mapping tables:

- **Windows**: `MultiByteToWideChar` / `WideCharToMultiByte`
- **Linux / Unix-like**: `iconv`
- **macOS**: `iconv` with explicit `iconv` system library linking
- **UTF-16 / UTF-32**: lightweight built-in byte-order handling

UTF-8 is the recommended internal representation.

## Supported Encodings

- Unicode: `ascii`, `utf8`, `utf16le`, `utf16be`, `utf32le`, `utf32be`
- CJK: `gb2312`, `gbk`, `gb18030`, `shift_jis`, `euc_jp`, `iso_2022_jp`, `big5`, `euc_kr`, `cp949`
- ISO: `iso_8859_1`, `iso_8859_2`, `iso_8859_5`, `iso_8859_15`
- Windows: `windows_1250` ... `windows_1258`
- Others: `koi8_r`, `koi8_u`, `mac_roman`, `ibm437`, `ibm850`

Backend availability depends on the platform. Use `isEncodingSupported()` or `isConversionSupported()` when support is not guaranteed.

## Installation

Add `lightenc` as a Zig package dependency:

```sh
zig fetch --save git+https://github.com/John2416/lightenc.git
```

Import it in `build.zig`:

```zig
const lightenc_dep = b.dependency("lightenc", .{
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "lightenc", .module = lightenc_dep.module("lightenc") },
    },
});
```

If your program uses platform backend conversions such as GBK, Shift_JIS, Big5, Windows-125x, or `iconv` conversions, link the required system libraries:

```zig
linkLightencBackend(exe_mod, target);
```

Recommended helper:

```zig
fn linkLightencBackend(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .linux,
        .freebsd,
        .netbsd,
        .openbsd,
        .dragonfly,
        .illumos,
        => {
            module.link_libc = true;
        },

        .macos,
        .ios,
        .tvos,
        .watchos,
        .visionos,
        => {
            module.link_libc = true;
            module.linkSystemLibrary("iconv", .{});
        },

        // Windows uses Win32 APIs from kernel32.
        .windows => {},
        else => {},
    }
}
```

For pure UTF-16 / UTF-32 byte-order helper usage only, this linker helper is not required. On Unix-like targets, call it when importing `lightenc` unless you are certain your build only uses pure Unicode helper paths and the linker can eliminate unused `iconv` references.

## Usage

```zig
const std = @import("std");
const enc = @import("lightenc");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // GBK bytes for "中文".
    const gbk = [_]u8{ 0xD6, 0xD0, 0xCE, 0xC4 };

    const utf8 = try enc.toUtf8Alloc(allocator, &gbk, .gbk, .{});
    defer allocator.free(utf8);

    std.debug.print("{s}\n", .{utf8});
}
```

Convert from UTF-8:

```zig
const gbk = try enc.fromUtf8Alloc(allocator, "中文", .gbk, .{ .policy = .strict });
defer allocator.free(gbk);
```

Convert between arbitrary encodings:

```zig
const out = try enc.convertAlloc(allocator, input, .gbk, .shift_jis, .{ .policy = .strict });
defer allocator.free(out);
```

Compile-time fixed transcoder:

```zig
const GbkToUtf8 = enc.Transcoder(.gbk, .utf8);
const out = try GbkToUtf8.convertAlloc(allocator, input, .{});
defer allocator.free(out);
```

## API

```zig
enc.convertAlloc(allocator, input, from, to, options)
enc.toUtf8Alloc(allocator, input, from, options)
enc.fromUtf8Alloc(allocator, input, to, options)
enc.parseEncoding(label)
enc.isEncodingSupported(encoding)
enc.isConversionSupported(from, to)
```

Options:

```zig
pub const Options = struct {
    policy: ErrorPolicy = .strict,
    validate_identity: bool = false,
    reject_misaligned_unicode: bool = true,
};
```

Policies:

- `strict`: fail on invalid input or unrepresentable output.
- `replace`: ask the backend to substitute when possible.
- `ignore`: backend-dependent; currently unsupported by the Windows backend.

## Platform Notes

### Windows

Windows uses Win32 code page APIs. Important mappings:

- `.gbk` -> CP936
- `.gb18030` -> CP54936
- `.shift_jis` -> CP932 / Windows-31J
- `.big5` -> CP950

Most non-Unicode conversions go through UTF-16 internally.

### Linux

Linux uses `iconv`. glibc usually has broad coverage; musl may support fewer legacy encodings or fewer conversion directions.

### macOS

macOS uses `iconv`, but you must link it explicitly:

```zig
module.linkSystemLibrary("iconv", .{});
```

## License

Apache-2.0
