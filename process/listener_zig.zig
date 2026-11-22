//! 受け取った文字列を表示する Process (listener_zig)。
const std = @import("std");
const juiz = @import("juiz");

fn listener(args: struct { arg1: []const u8 = "Hello, Juiz!" }) []const u8 {
    std.debug.print("listener_zig: {s}\n", .{args.arg1});
    return args.arg1;
}

comptime {
    juiz.exportProcess(listener, .{
        .type_name = "listener_zig",
        .description = "Prints the received message.",
        .args = .{ .arg1 = "message to be printed" },
    });
}
