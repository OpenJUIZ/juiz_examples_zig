//! arg1 に 1 を足して返す Process (increment_process_zig)。
const std = @import("std");
const juiz = @import("juiz");

/// 引数は 1 つの struct で受ける。フィールドの名前・型・既定値が、そのままマニフェストの引数になる
fn increment(args: struct { arg1: i64 = 1 }) !i64 {
    // i64 の最大値に足すと error.Overflow を返す (juiz にはエラーとして返る)
    return std.math.add(i64, args.arg1, 1);
}

comptime {
    juiz.exportProcess(increment, .{
        .type_name = "increment_process_zig",
        .description = "Adds 1 to arg1.",
        .args = .{ .arg1 = "value to be incremented" },
    });
}
