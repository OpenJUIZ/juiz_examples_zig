//! juiz の Zig 版サンプルのビルド。ふだんは build.sh から呼ぶ:
//!
//!   zig build --release --prefix build -Djuiz-sdk-lib=<libjuiz_sdk のあるディレクトリの絶対パス>
//!
//! プラグインは juiz.installBundle で <prefix>/plugins (build.sh では build/plugins) に、libjuiz_sdk と並べて置く。
//! rpath は $ORIGIN (macOS は @loader_path) だけなので、そのディレクトリごと .juizapp に入れられる。
const std = @import("std");
const zigjuiz = @import("zigjuiz");

/// サンプルの一覧。名前はライブラリの名前 (lib<名前>.so など) で、conf の plugins に書く名前と同じ
const plugins = [_]struct { name: []const u8, path: []const u8, typed: bool = false }{
    // Process
    .{ .name = "increment_process_zig", .path = "process/increment_process_zig.zig" },
    .{ .name = "decrement_process_zig", .path = "process/decrement_process_zig.zig" },
    .{ .name = "talker_zig", .path = "process/talker_zig.zig" },
    .{ .name = "listener_zig", .path = "process/listener_zig.zig" },
    // 型付きの引数・戻り値 (types/geometry.jidl の型を使う)
    .{ .name = "pose_move_zig", .path = "process/pose_move_zig.zig", .typed = true },
    // Container と ContainerProcess (別々のライブラリ。状態の型は container/example_container_state.zig)
    .{ .name = "example_container_zig", .path = "container/example_container_zig.zig" },
    .{ .name = "example_container_zig_increment", .path = "container/example_container_zig_increment.zig" },
    .{ .name = "example_container_zig_get", .path = "container/example_container_zig_get.zig" },
    // Component (1 つのライブラリにまとめる)
    .{ .name = "example_component_zig", .path = "component/example_component_zig.zig" },
    .{ .name = "mobile_robot_zig", .path = "component/mobile_robot_zig.zig" },
};

pub fn build(b: *std.Build) void {
    const juiz = zigjuiz.init(b, .{
        .target = b.standardTargetOptions(.{}),
        // --release のときは ReleaseSafe (範囲外アクセスなどの安全検査を残す)
        .optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe }),
    });
    // サンプル共通の型。juiz-idl -g zig で作る (-Djuiz-idl か PATH の juiz-idl、無ければ `juiz idl`)
    const types = juiz.addTypes(.{ .files = &.{b.path("types/geometry.jidl")} });
    for (plugins) |p| {
        const lib = juiz.addPlugin(.{
            .name = p.name,
            .root_source_file = b.path(p.path),
            .imports = if (p.typed) &.{.{ .name = "juiz_types", .module = types }} else &.{},
        });
        juiz.installBundle(lib, .{});
    }
}
