//! 整数値を 1 つ保持する Container (example_container_zig)。
//! 初期値は設定ファイルの containers に書いた value (無ければ 0)。
const juiz = @import("juiz");
const state = @import("example_container_state.zig");

/// 返した値を zigjuiz が Container の状態として持つ
fn create(args: struct { value: i64 = 0 }) state.Counter {
    return .{ .value = args.value };
}

comptime {
    juiz.exportContainer(create, .{
        .type_name = "example_container_zig",
        .description = "Holds an integer value.",
        .args = .{ .value = "initial value" },
    });
}
