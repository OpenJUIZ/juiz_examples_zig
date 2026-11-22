//! example_container_zig の値に arg1 を足し、足した後の値を返す ContainerProcess (example_container_zig_increment)。
const std = @import("std");
const juiz = @import("juiz");
const state = @import("example_container_state.zig");

/// 最初の引数 self で Container の状態を受け取る
fn increment(self: *state.Counter, args: struct { arg1: i64 = 1 }) !i64 {
    self.value = try std.math.add(i64, self.value, args.arg1);
    return self.value;
}

comptime {
    juiz.exportContainerProcess(increment, .{
        .type_name = "example_container_zig_increment",
        .container_type = "example_container_zig",
        .description = "Adds arg1 to the value of the container.",
        .args = .{ .arg1 = "value to be added" },
    });
}
