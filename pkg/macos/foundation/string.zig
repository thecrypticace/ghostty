const std = @import("std");
const Allocator = std.mem.Allocator;
const foundation = @import("../foundation.zig");
const c = @import("c.zig");

pub const String = opaque {
    pub fn createWithBytes(
        bs: []const u8,
        encoding: StringEncoding,
        external: bool,
    ) Allocator.Error!*String {
        return @intToPtr(?*String, @ptrToInt(c.CFStringCreateWithBytes(
            null,
            bs.ptr,
            @intCast(c_long, bs.len),
            @enumToInt(encoding),
            @boolToInt(external),
        ))) orelse Allocator.Error.OutOfMemory;
    }

    pub fn release(self: *String) void {
        c.CFRelease(self);
    }

    pub fn hasPrefix(self: *String, prefix: *String) bool {
        return c.CFStringHasPrefix(
            @ptrCast(c.CFStringRef, self),
            @ptrCast(c.CFStringRef, prefix),
        ) == 1;
    }

    pub fn compare(
        self: *String,
        other: *String,
        options: StringComparison,
    ) foundation.ComparisonResult {
        return @intToEnum(
            foundation.ComparisonResult,
            c.CFStringCompare(
                @ptrCast(c.CFStringRef, self),
                @ptrCast(c.CFStringRef, other),
                @intCast(c_ulong, @bitCast(c_int, options)),
            ),
        );
    }

    pub fn cstring(self: *String, buf: []u8, encoding: StringEncoding) ?[]const u8 {
        if (c.CFStringGetCString(
            @ptrCast(c.CFStringRef, self),
            buf.ptr,
            @intCast(c_long, buf.len),
            @enumToInt(encoding),
        ) == 0) return null;
        return std.mem.sliceTo(buf, 0);
    }

    pub fn cstringPtr(self: *String, encoding: StringEncoding) ?[:0]const u8 {
        const ptr = c.CFStringGetCStringPtr(
            @ptrCast(c.CFStringRef, self),
            @enumToInt(encoding),
        );
        if (ptr == null) return null;
        return std.mem.sliceTo(ptr, 0);
    }
};

pub const StringComparison = packed struct {
    case_insensitive: bool = false,
    _unused_2: bool = false,
    backwards: bool = false,
    anchored: bool = false,
    nonliteral: bool = false,
    localized: bool = false,
    numerically: bool = false,
    diacritic_insensitive: bool = false,
    width_insensitive: bool = false,
    forced_ordering: bool = false,
    _padding: u22 = 0,

    test {
        try std.testing.expectEqual(@bitSizeOf(c_int), @bitSizeOf(StringComparison));
    }
};

/// https://developer.apple.com/documentation/corefoundation/cfstringencoding?language=objc
pub const StringEncoding = enum(u32) {
    invalid = 0xffffffff,
    mac_roman = 0,
    windows_latin1 = 0x0500,
    iso_latin1 = 0x0201,
    nextstep_latin = 0x0B01,
    ascii = 0x0600,
    unicode = 0x0100,
    utf8 = 0x08000100,
    non_lossy_ascii = 0x0BFF,
    utf16_be = 0x10000100,
    utf16_le = 0x14000100,
    utf32 = 0x0c000100,
    utf32_be = 0x18000100,
    utf32_le = 0x1c000100,
};

test "string" {
    const testing = std.testing;

    const str = try String.createWithBytes("hello world", .ascii, false);
    defer str.release();

    const prefix = try String.createWithBytes("hello", .ascii, false);
    defer prefix.release();

    try testing.expect(str.hasPrefix(prefix));
    try testing.expectEqual(foundation.ComparisonResult.equal, str.compare(str, .{}));
    try testing.expectEqualStrings("hello world", str.cstringPtr(.ascii).?);

    {
        var buf: [128]u8 = undefined;
        const cstr = str.cstring(&buf, .ascii).?;
        try testing.expectEqualStrings("hello world", cstr);
    }
}