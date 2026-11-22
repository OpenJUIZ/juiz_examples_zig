//! arg1 から 1 を引いて返す Process (decrement_process_zig)。
//! エラーを返さない関数は、戻り値をエラー共用体 (!T) にしなくてよい。
const juiz = @import("juiz");

fn decrement(args: struct { arg1: i64 = 1 }) i64 {
    return args.arg1 -% 1;
}

comptime {
    juiz.exportProcess(decrement, .{
        .type_name = "decrement_process_zig",
        .description = "Subtracts 1 from arg1.",
        .args = .{ .arg1 = "value to be decremented" },
    });
}
