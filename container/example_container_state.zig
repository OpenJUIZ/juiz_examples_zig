//! example_container_zig の状態の型。
//!
//! Container (example_container_zig.zig) と ContainerProcess (example_container_zig_increment.zig など) は
//! 別々の共有ライブラリになるので、どちらからもこのファイルを @import して型をそろえる。
//! zigjuiz は状態の型の名前 (example_container_state.Counter) などから作った目印で、渡された Container が
//! 期待する型かを確かめる (違えば -1104 のエラー)。

/// 保持している値
pub const Counter = struct {
    value: i64,
};
