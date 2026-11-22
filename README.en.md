# juiz_examples_zig

[日本語](README.md)

Zig examples for [juiz](https://github.com/OpenJUIZ/juiz), a middleware for robots and IoT.
Processes and Containers written in Zig are built as shared libraries (plugins), and the `juiz` command loads them as described in a configuration file (`*.conf`).

Examples in other languages: [Rust](https://github.com/OpenJUIZ/juiz_examples_rust), [Python](https://github.com/OpenJUIZ/juiz_examples_python), [C++](https://github.com/OpenJUIZ/juiz_examples_cpp), [Haskell](https://github.com/OpenJUIZ/juiz_examples_haskell).

> **Zig support is not in a released version of juiz yet.** Until the first version that ships zigjuiz (the Zig library) is released, this repository is pinned to a commit on juiz's main branch (`5700911`), and the `juiz` command is installed from that commit too. After the release, it switches to the released `juiz` command and to `zigjuiz-<version>.tar.gz` from juiz's Releases (fetched with `zig fetch`).

## How it works

Plugins are written with zigjuiz (`bindings/zigjuiz` in juiz, `@import("juiz")`) and linked to `libjuiz_sdk`, the shared library of juiz_sdk.
zigjuiz generates, at comptime, the C functions juiz looks for, so no runtime is added to the plugin.

[build.sh](build.sh) does the following:

1. Fetches the juiz source into `build/juiz` ([build.zig.zon](build.zig.zon) refers to its `bindings/zigjuiz`)
2. Builds juiz_sdk from that source with `cargo build --release -p juiz_sdk` (when `JUIZ_GIT_REF` is a tag `v<version>`, downloads the `libjuiz_sdk` archive of that version instead)
3. Runs `zig build` and puts the plugins and `libjuiz_sdk` side by side in `build/plugins`. The shared types (`types/geometry.jidl`) are generated during the build by `juiz idl -g zig`

The plugins are installed with zigjuiz's `installBundle`, so their rpath is only their own directory (`$ORIGIN`, `@loader_path` on macOS), and the files in `build/plugins` can go into a `.juizapp` as they are.

## Requirements

- Linux, macOS or Windows (x86_64). On Windows, run `./build.sh` in Git Bash with Rust's MSVC toolchain
- **Zig 0.17.x** (zigjuiz supports exactly one Zig version; build.sh and zigjuiz's build.zig stop with an error on other versions). Get it from https://ziglang.org/download/, or `pip install ziglang==0.17.1` and run with `ZIG="python3 -m ziglang"`
- Rust (stable), to build the `juiz` command and libjuiz_sdk (https://rustup.rs/)
- git
- On Linux, Python development files to build the `juiz` command (`sudo apt install python3-dev` on Ubuntu)
- The Python processes of the data type example (`typed_pose.conf`) use pyjuiz

## 1. Install the juiz command

```sh
cargo install juiz_app --git https://github.com/OpenJUIZ/juiz --rev 5700911b1017e4e63f933e90a966c9352e9ece31 --locked
pip install "pyjuiz @ git+https://github.com/OpenJUIZ/juiz@5700911b1017e4e63f933e90a966c9352e9ece31#subdirectory=bindings/pyjuiz"
```

## 2. Build the examples

```sh
git clone https://github.com/OpenJUIZ/juiz_examples_zig.git
cd juiz_examples_zig
./build.sh
```

The plugins are written to `build/plugins`. The configuration files look for plugins in `./build/plugins`, so run `juiz` **at the root of the repository**.
To use a local juiz source, run `JUIZ_SOURCE_DIR=/path/to/juiz ./build.sh`.

## 3. Run

### Process: increment_process_zig

A Process that adds 1 to its argument ([process/increment_process_zig.zig](process/increment_process_zig.zig)).

```zig
const std = @import("std");
const juiz = @import("juiz");

fn increment(args: struct { arg1: i64 = 1 }) !i64 {
    return std.math.add(i64, args.arg1, 1);
}

comptime {
    juiz.exportProcess(increment, .{
        .type_name = "increment_process_zig",
        .description = "Adds 1 to arg1.",
        .args = .{ .arg1 = "value to be incremented" },
    });
}
```

Arguments are taken as one struct: the field names, types and default values become the arguments in the manifest, and `.args` gives their descriptions (a missing description is a compile error). A Zig error returned by the function becomes an error of the juiz call.

```sh
juiz -f increment_process.conf -d
# in another terminal
juiz process call "http://127.0.0.1:8000/process/increment0::increment_process_zig" '{"arg1": 3}' -p
# => CapsulePtr((value:Value(4), option: []))
juiz -f decrement_process.conf -d
juiz process call "http://127.0.0.1:8000/process/decrement0::decrement_process_zig" '{"arg1": 3}' -p
# => CapsulePtr((value:Value(2), option: []))
```

### Connecting Processes: talker / listener

```sh
juiz -f talker_listener.conf -d
# talker_zig: Hello, Juiz!
# listener_zig: Hello, Juiz!
```

### Container: example_container_zig

A Container holding an integer and its ContainerProcesses (`example_container_zig_increment`, `example_container_zig_get`). They are separate libraries, so both `@import` the state type from [container/example_container_state.zig](container/example_container_state.zig). zigjuiz checks that the Container passed to a ContainerProcess has the expected state type (error `-1104` otherwise). A ContainerProcess receives the state as its first argument `self`; taking `self` as `*const` makes it readonly.

```sh
juiz -f example_container.conf -d
juiz container-process call "http://127.0.0.1:8000/container_process/increment0::example_container_zig_increment:container0" '{"arg1": 5}' -p
# => CapsulePtr((value:Value(15), option: []))
juiz container-process call "http://127.0.0.1:8000/container_process/get0::example_container_zig_get:container0" '{}' -p
# => CapsulePtr((value:Value(15), option: []))
```

### Component: example_component_zig

A Component puts Processes, a Container and ContainerProcesses into one library with `juiz.exportComponent` ([component/example_component_zig.zig](component/example_component_zig.zig)).

```sh
juiz -f example_component.conf -d
juiz process call "http://127.0.0.1:8000/process/proc0::example_component_zig_increment" '{"arg1": 1}' -p
# => CapsulePtr((value:Value(2), option: []))
juiz container-process call "http://127.0.0.1:8000/container_process/increment0::example_component_zig_container_increment:container0" '{"arg1": 5}' -p
# => CapsulePtr((value:Value(105), option: []))
```

### Namespaces

`namespace.conf` places `talker0` / `listener0` in two namespaces `robot1` and `robot2`. `--namespace` replaces the default namespace of a configuration file.

```sh
juiz -f namespace.conf -d
juiz process call "http://127.0.0.1:8000/process/robot1/talker0::talker_zig" '{"message": "Hi"}' -p
```

### Data types across languages

[types/geometry.jidl](types/geometry.jidl) is the same in the Zig, Rust, Python, C++ and Haskell example repositories, so the type fingerprints match in every language. `pose_move_zig` ([process/pose_move_zig.zig](process/pose_move_zig.zig)) uses `Pose2D` and `Twist2D` generated by `juiz.addTypes` in [build.zig](build.zig). In `typed_pose.conf`, a Python process sends `Twist2D` to `pose_move_zig`, which sends `Pose2D` to another Python process. `typed_mismatch.conf` shows that mismatched types are not connected.

```sh
juiz idl -g python -o gen types/geometry.jidl
juiz -f typed_pose.conf -d
juiz process call "http://127.0.0.1:8000/process/move0::pose_move_zig" '{"pose": {"position": {"x": 1.0, "y": 2.0}}, "twist": {"linear": 1.0}, "dt": 2.0}' -p
# => CapsulePtr((value:Value({"frame_id":"map","position":{"x":3.0,"y":2.0},"theta":0.0}), option: []))
```

### Transformations

`transformations.conf` builds the tree `map → odom → base0 (mobile base) → pantilt0 → camera0` with the parts in [component/mobile_robot_zig.zig](component/mobile_robot_zig.zig). ContainerProcesses read and write their pose with `juiz.pose(self, reference)` and `juiz.setPose(self, reference, pose)`. `transformations_map.conf` and `transformations_robot.conf` split the tree into two Systems.

```sh
juiz -f transformations.conf -d
juiz container-process call "http://127.0.0.1:8000/container_process/move0::mobile_base_zig_move:base0" '{"vx": 1.0, "dt": 1.0}' -p
juiz container-process call "http://127.0.0.1:8000/container_process/pan0::pantilt_zig_set_pan:pantilt0" '{"pan": 1.5707963267948966}' -p
juiz container pose camera0 --reference map
# => position: x=2.1, y=2.05, z=0.32
```

### Distributing as .juizapp

```sh
python3 scripts/make_packages.py      # after ./build.sh
juiz run dist/talker_listener-0.1.0-x86_64-unknown-linux-gnu.juizapp
```

Zig plugins only need `libjuiz_sdk`, so the script just copies the plugins and `libjuiz_sdk` from `build/plugins` into `plugins/<target>/` and calls `juiz pack`.

## Tests

`python3 tests/test_examples.py` (after `./build.sh`) runs every example above and checks the results. CI runs it on Linux for pull requests, and on Linux, macOS and Windows for pushes to main, tags and manual runs.

## License

Licensed under either of Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE)) or MIT license ([LICENSE-MIT](LICENSE-MIT)) at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
