//! A deferred face represents a single font face with all the information
//! necessary to load it, but defers loading the full face until it is
//! needed.
//!
//! This allows us to have many fallback fonts to look for glyphs, but
//! only load them if they're really needed.
const DeferredFace = @This();

const std = @import("std");
const assert = std.debug.assert;
const fontconfig = @import("fontconfig");
const options = @import("main.zig").options;
const Library = @import("main.zig").Library;
const Face = @import("main.zig").Face;
const Presentation = @import("main.zig").Presentation;

/// The loaded face (once loaded).
face: ?Face = null,

/// Fontconfig
fc: if (options.fontconfig) ?Fontconfig else void = if (options.fontconfig) null else {},

/// Fontconfig specific data. This is only present if building with fontconfig.
pub const Fontconfig = struct {
    /// The pattern for this font. This must be the "render prepared" pattern.
    /// (i.e. call FcFontRenderPrepare).
    pattern: *fontconfig.Pattern,

    /// Charset and Langset are used for quick lookup if a codepoint and
    /// presentation style are supported. They can be derived from pattern
    /// but are cached since they're frequently used.
    charset: *const fontconfig.CharSet,
    langset: *const fontconfig.LangSet,

    pub fn deinit(self: *Fontconfig) void {
        self.pattern.destroy();
        self.* = undefined;
    }
};

/// Initialize a deferred face that is already pre-loaded. The deferred face
/// takes ownership over the loaded face, deinit will deinit the loaded face.
pub fn initLoaded(face: Face) DeferredFace {
    return .{ .face = face };
}

pub fn deinit(self: *DeferredFace) void {
    if (self.face) |*face| face.deinit();
    if (options.fontconfig) if (self.fc) |*fc| fc.deinit();
    self.* = undefined;
}

/// Returns true if the face has been loaded.
pub inline fn loaded(self: DeferredFace) bool {
    return self.face != null;
}

/// Returns the name of this face. The memory is always owned by the
/// face so it doesn't have to be freed.
pub fn name(self: DeferredFace) ![:0]const u8 {
    if (options.fontconfig) {
        if (self.fc) |fc|
            return (try fc.pattern.get(.fullname, 0)).string;
    }

    return "TODO: built-in font names";
}

/// Load the deferred font face. This does nothing if the face is loaded.
pub fn load(
    self: *DeferredFace,
    lib: Library,
    size: Face.DesiredSize,
) !void {
    // No-op if we already loaded
    if (self.face != null) return;

    if (options.fontconfig) {
        try self.loadFontconfig(lib, size);
        return;
    }

    // Unreachable because we must be already loaded or have the
    // proper configuration for one of the other deferred mechanisms.
    unreachable;
}

fn loadFontconfig(
    self: *DeferredFace,
    lib: Library,
    size: Face.DesiredSize,
) !void {
    assert(self.face == null);
    const fc = self.fc.?;

    // Filename and index for our face so we can load it
    const filename = (try fc.pattern.get(.file, 0)).string;
    const face_index = (try fc.pattern.get(.index, 0)).integer;

    self.face = try Face.initFile(lib, filename, face_index, size);
}

/// Returns true if this face can satisfy the given codepoint and
/// presentation. If presentation is null, then it just checks if the
/// codepoint is present at all.
///
/// This should not require the face to be loaded IF we're using a
/// discovery mechanism (i.e. fontconfig). If no discovery is used,
/// the face is always expected to be loaded.
pub fn hasCodepoint(self: DeferredFace, cp: u32, p: ?Presentation) bool {
    // If we have the face, use the face.
    if (self.face) |face| {
        if (p) |desired| if (face.presentation != desired) return false;
        return face.glyphIndex(cp) != null;
    }

    // If we are using fontconfig, use the fontconfig metadata to
    // avoid loading the face.
    if (options.fontconfig) {
        if (self.fc) |fc| {
            // Check if char exists
            if (!fc.charset.hasChar(cp)) return false;

            // If we have a presentation, check it matches
            if (p) |desired| {
                const emoji_lang = "und-zsye";
                const actual: Presentation = if (fc.langset.hasLang(emoji_lang))
                    .emoji
                else
                    .text;

                return desired == actual;
            }

            return true;
        }
    }

    // This is unreachable because discovery mechanisms terminate, and
    // if we're not using a discovery mechanism, the face MUST be loaded.
    unreachable;
}

test "preloaded" {
    const testing = std.testing;
    const testFont = @import("test.zig").fontRegular;

    var lib = try Library.init();
    defer lib.deinit();

    var face = try Face.init(lib, testFont, .{ .points = 12 });
    errdefer face.deinit();

    var def = initLoaded(face);
    defer def.deinit();

    try testing.expect(def.hasCodepoint(' ', null));
}

test "fontconfig" {
    if (!options.fontconfig) return error.SkipZigTest;

    const discovery = @import("main.zig").discovery;
    const testing = std.testing;

    // Load freetype
    var lib = try Library.init();
    defer lib.deinit();

    // Get a deferred face from fontconfig
    var def = def: {
        var fc = discovery.Fontconfig.init();
        var it = try fc.discover(.{ .family = "monospace", .size = 12 });
        defer it.deinit();
        break :def (try it.next()).?;
    };
    defer def.deinit();
    try testing.expect(!def.loaded());

    // Verify we can get the name
    const n = try def.name();
    try testing.expect(n.len > 0);

    // Load it and verify it works
    try def.load(lib, .{ .points = 12 });
    try testing.expect(def.hasCodepoint(' ', null));
    try testing.expect(def.face.?.glyphIndex(' ') != null);
}