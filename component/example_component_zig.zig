//! 1 つのライブラリに Process・Container・ContainerProcess をまとめた Component (example_component_zig)。
//!
//! 各要素の関数を単体のときと同じように書き、juiz.exportComponent の .parts に並べて公開する。
//! Container と ContainerProcess が同じライブラリに入るので、状態の型を別のファイルに分けなくてよい。
const std = @import("std");
const juiz = @import("juiz");

/// Process: arg1 に 1 を足して返す
fn increment(args: struct { arg1: i64 = 1 }) !i64 {
    return std.math.add(i64, args.arg1, 1);
}

/// Container の状態: 整数値を 1 つ保持する
const ComponentContainer = struct {
    value: i64,
};

fn createContainer(args: struct { value: i64 = 0 }) ComponentContainer {
    return .{ .value = args.value };
}

/// ContainerProcess: Container の値を返す (readonly)
fn containerGet(self: *const ComponentContainer) i64 {
    return self.value;
}

/// ContainerProcess: Container の値に arg1 を足す
fn containerIncrement(self: *ComponentContainer, args: struct { arg1: i64 = 1 }) !i64 {
    self.value = try std.math.add(i64, self.value, args.arg1);
    return self.value;
}

comptime {
    juiz.exportComponent(.{
        .type_name = "example_component_zig",
        .description = "Zig component example.",
        .parts = .{
            juiz.processPart(increment, .{
                .type_name = "example_component_zig_increment",
                .description = "Adds 1 to arg1.",
                .args = .{ .arg1 = "value to be incremented" },
            }),
            juiz.containerPart(createContainer, .{
                .type_name = "example_component_zig_container",
                .description = "Holds an integer value.",
                .args = .{ .value = "initial value" },
            }),
            juiz.containerProcessPart(containerGet, .{
                .type_name = "example_component_zig_container_get",
                .container_type = "example_component_zig_container",
                .description = "Returns the value of the container.",
            }),
            juiz.containerProcessPart(containerIncrement, .{
                .type_name = "example_component_zig_container_increment",
                .container_type = "example_component_zig_container",
                .description = "Adds arg1 to the value of the container.",
                .args = .{ .arg1 = "value to be added" },
            }),
        },
    });
}
