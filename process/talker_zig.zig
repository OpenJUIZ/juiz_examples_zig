//! 文字列 message (既定は "Hello, Juiz!") を出力する Process (talker_zig)。
const std = @import("std");
const juiz = @import("juiz");

/// 文字列は []const u8 で受け取る。受け取った文字列は呼び出しの間だけ有効で、そのまま返してよい
fn talker(args: struct { message: []const u8 = "Hello, Juiz!" }) []const u8 {
    // std.debug.print は標準エラーに書く (バッファしないので、すぐに出る)
    std.debug.print("talker_zig: {s}\n", .{args.message});
    return args.message;
}

comptime {
    juiz.exportProcess(talker, .{
        .type_name = "talker_zig",
        .description = "Outputs a message.",
        .args = .{ .message = "message to be output" },
    });
}
