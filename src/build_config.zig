//! Build options, available at comptime. Used to configure features. This
//! will reproduce some of the fields from builtin and build_options just
//! so we can limit the amount of imports we need AND give us the ability
//! to shim logic and values into them later.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const assert = std.debug.assert;
const apprt = @import("apprt.zig");
const font = @import("font/main.zig");

/// The artifact we're producing. This can be used to determine if we're
/// building a standalone exe, an embedded lib, etc.
pub const artifact = Artifact.detect();

/// The runtime to back exe artifacts with.
pub const app_runtime: apprt.Runtime = switch (artifact) {
    .lib => .none,
    else => std.meta.stringToEnum(apprt.Runtime, std.meta.tagName(options.app_runtime)).?,
};

/// The font backend desired for the build.
pub const font_backend: font.Backend = std.meta.stringToEnum(
    font.Backend,
    std.meta.tagName(options.font_backend),
).?;

/// Whether our devmode UI is enabled or not. This requires imgui to be
/// compiled.
pub const devmode_enabled = artifact == .exe and app_runtime == .glfw;

/// We want to integrate with Flatpak APIs.
pub const flatpak = options.flatpak;

pub const Artifact = enum {
    /// Standalone executable
    exe,

    /// Embeddable library
    lib,

    /// The WASM-targetted module.
    wasm_module,

    pub fn detect() Artifact {
        if (builtin.target.isWasm()) {
            assert(builtin.output_mode == .Obj);
            assert(builtin.link_mode == .Static);
            return .wasm_module;
        }

        return switch (builtin.output_mode) {
            .Exe => .exe,
            .Lib => .lib,
            else => {
                @compileLog(builtin.output_mode);
                @compileError("unsupported artifact output mode");
            },
        };
    }
};