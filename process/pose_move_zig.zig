//! 姿勢 pose から速度 twist で dt 秒動いた姿勢を返す Process (pose_move_zig)。
//!
//! 引数と戻り値が型付き (examples.geometry の Pose2D・Twist2D) なので、型の合わない Process とは接続できない。
//! 型は build.zig の juiz.addTypes が types/geometry.jidl から juiz-idl -g zig で作り、juiz_types という名前で読み込む。
const std = @import("std");
const juiz = @import("juiz");
const geometry = @import("juiz_types").examples.geometry;

const Pose2D = geometry.Pose2D;
const Twist2D = geometry.Twist2D;

/// 型付きの引数の既定値は型の値で書く (.{} は全フィールドが既定値)。
/// 結果が型付きの型なので、戻り値の型 (output_schema) もマニフェストに載る
fn poseMove(args: struct { pose: Pose2D = .{}, twist: Twist2D = .{}, dt: f64 = 1 }) Pose2D {
    const p = args.pose;
    const distance = args.twist.linear * args.dt;
    var moved = p;
    moved.position.x = p.position.x + distance * @cos(p.theta);
    moved.position.y = p.position.y + distance * @sin(p.theta);
    moved.theta = p.theta + args.twist.angular * args.dt;
    std.debug.print("pose_move_zig: ({d:.2}, {d:.2}, {d:.2}) -> ({d:.2}, {d:.2}, {d:.2})\n", .{
        p.position.x, p.position.y, p.theta, moved.position.x, moved.position.y, moved.theta,
    });
    return moved;
}

comptime {
    juiz.exportProcess(poseMove, .{
        .type_name = "pose_move_zig",
        .description = "Moves the pose by the twist for dt seconds.",
        .args = .{ .pose = "current pose", .twist = "velocity", .dt = "duration [s]" },
    });
}
