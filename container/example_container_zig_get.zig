//! example_container_zig の値を返す ContainerProcess (example_container_zig_get)。引数は無い。
//! 状態を *const で受けるので readonly の ContainerProcess になる (同じ Container の readonly 同士は並行に走る)。
const juiz = @import("juiz");
const state = @import("example_container_state.zig");

fn get(self: *const state.Counter) i64 {
    return self.value;
}

comptime {
    juiz.exportContainerProcess(get, .{
        .type_name = "example_container_zig_get",
        .container_type = "example_container_zig",
        .description = "Returns the value of the container.",
    });
}
