//! Transformations のサンプル: 台車 → 雲台 → カメラ の部品 (mobile_robot_zig)。
//!
//! 位置姿勢 (ContainerPose) は juiz が Container ごとに持ち、利用者の状態とは別にある。
//! 部品のつながり (Transform) と基点 (Anchor) は transformations.conf に書く:
//!
//!     map (Periodic) → odom (Static) → base0 (mobile_base_zig) → pantilt0 (pantilt_zig) → camera0 (camera_zig)
//!
//! - mobile_base_zig_move はオドメトリを積分して、odom から見た自分の位置姿勢を juiz.setPose で書く。
//! - pantilt_zig_set_pan はパン角を書く (台車から見た自分の向きだけを変える)。
//! - camera_zig_pose は基準から見た自分の位置姿勢を juiz.pose で読む。カメラは Transform で雲台につながっているだけ。
//!   状態を *const で受けるので readonly の ContainerProcess になる。
//! - pose_print_zig は Pose 通知 (conf の pose_listeners:) で呼ばれる Process。
//!
//! juiz.pose / juiz.setPose の最初の引数には、ContainerProcess が受け取った self を渡す。
const std = @import("std");
const juiz = @import("juiz");

/// 台車。オドメトリ (odom から見た x, y, 向き theta) を自分で積分して持つ
const MobileBase = struct {
    x: f64 = 0,
    y: f64 = 0,
    theta: f64 = 0,
};

fn createMobileBase() MobileBase {
    return .{};
}

/// 速度 vx [m/s]・角速度 omega [rad/s] で dt [s] 動かし、基準 reference (odom) から見た位置姿勢を書く
fn move(self: *MobileBase, ctx: juiz.Context, args: struct {
    vx: f64 = 0,
    omega: f64 = 0,
    dt: f64 = 1,
    reference: []const u8 = "odom",
}) !juiz.Value {
    self.x += args.vx * @cos(self.theta) * args.dt;
    self.y += args.vx * @sin(self.theta) * args.dt;
    self.theta += args.omega * args.dt;
    // odom → base0 の Transform が書き換わり、Pose 通知が出る
    const written = try juiz.setPose(self, args.reference, juiz.makePose2d(self.x, self.y, self.theta));
    return juiz.poseStampedToValue(ctx.allocator, written, args.reference);
}

/// 雲台。パン角を持つ
const Pantilt = struct {
    pan: f64 = 0,
};

fn createPantilt() Pantilt {
    return .{};
}

/// パン角 pan [rad] にする。取り付け位置はそのままで、基準 reference (台車) から見た向きだけを変える
fn setPan(self: *Pantilt, ctx: juiz.Context, args: struct {
    pan: f64 = 0,
    reference: []const u8 = "base0",
}) !juiz.Value {
    self.pan = args.pan;
    const now = try juiz.pose(self, args.reference);
    const mount = now.pose.position;
    const written = try juiz.setPose(self, args.reference, juiz.makePose(mount.x, mount.y, mount.z, juiz.fromRpy(0, 0, args.pan)));
    return juiz.poseStampedToValue(ctx.allocator, written, args.reference);
}

/// カメラ。利用者の状態は持たない
const Camera = struct {};

fn createCamera() Camera {
    return .{};
}

/// 基準 reference から見た自分の位置姿勢 (juiz_std.geometry.PoseStamped の辞書)。
/// self を *const で受けるので readonly。juiz は Container を読み出しロックで呼ぶので、同じ Container の
/// readonly 同士は並行に走る。readonly の中から juiz.setPose を呼ぶとコンパイルエラーになる
fn cameraPose(self: *const Camera, ctx: juiz.Context, args: struct { reference: []const u8 = "map" }) !juiz.Value {
    const p = try juiz.pose(self, args.reference);
    return juiz.poseStampedToValue(ctx.allocator, p, args.reference);
}

/// 辞書に無いキーを読んだときの値
const none: juiz.Value = .null;

/// Pose 通知の受け手。受け取った位置姿勢 (juiz_std.geometry.PoseStamped の辞書) を表示する
fn posePrint(ctx: juiz.Context, args: struct { pose: juiz.Value = .{ .object = &.{} } }) ![]const u8 {
    const pose = args.pose.get("pose") orelse none;
    const position = pose.get("position") orelse none;
    const orientation = pose.get("orientation") orelse none;
    const num = struct {
        fn f(v: juiz.Value, key: []const u8) f64 {
            return (v.get(key) orelse return 0).asFloat() orelse 0;
        }
    }.f;
    const q: juiz.Quaternion = .{
        .x = num(orientation, "x"),
        .y = num(orientation, "y"),
        .z = num(orientation, "z"),
        .w = num(orientation, "w"),
    };
    const header = args.pose.get("header") orelse none;
    const frame_id = (header.get("frame_id") orelse none).asString() orelse "";
    const text = try std.fmt.allocPrint(ctx.allocator, "pose_print_zig: x={d:.2} y={d:.2} yaw={d:.1}deg (from {s})", .{
        num(position, "x"), num(position, "y"), juiz.yaw(q) * 180 / std.math.pi, frame_id,
    });
    std.debug.print("{s}\n", .{text});
    return text;
}

comptime {
    juiz.exportComponent(.{
        .type_name = "mobile_robot_zig",
        .description = "Parts of a mobile robot (base, pan-tilt and camera) for Transformations.",
        .parts = .{
            juiz.processPart(posePrint, .{
                .type_name = "pose_print_zig",
                .description = "Prints the received ContainerPose.",
                .args = .{ .pose = "juiz_std.geometry.PoseStamped" },
            }),
            juiz.containerPart(createMobileBase, .{
                .type_name = "mobile_base_zig",
                .description = "Mobile base. Integrates its odometry.",
            }),
            juiz.containerProcessPart(move, .{
                .type_name = "mobile_base_zig_move",
                .container_type = "mobile_base_zig",
                .args = .{
                    .vx = "velocity [m/s]",
                    .omega = "angular velocity [rad/s]",
                    .dt = "time step [s]",
                    .reference = "reference container",
                },
            }),
            juiz.containerPart(createPantilt, .{
                .type_name = "pantilt_zig",
                .description = "Pan-tilt unit. Holds its pan angle.",
            }),
            juiz.containerProcessPart(setPan, .{
                .type_name = "pantilt_zig_set_pan",
                .container_type = "pantilt_zig",
                .args = .{ .pan = "pan angle [rad]", .reference = "reference container" },
            }),
            juiz.containerPart(createCamera, .{
                .type_name = "camera_zig",
                .description = "Camera. Attached to the pan-tilt unit by a Transform.",
            }),
            juiz.containerProcessPart(cameraPose, .{
                .type_name = "camera_zig_pose",
                .container_type = "camera_zig",
                .args = .{ .reference = "reference container" },
            }),
        },
    });
}
