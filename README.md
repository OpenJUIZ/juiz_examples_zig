# juiz_examples_zig

[English](README.en.md)

ロボット・IoT 向けミドルウェア [juiz](https://github.com/OpenJUIZ/juiz) の Zig 版サンプル集です。
Zig で書いた Process・Container を共有ライブラリ (プラグイン) にし、`juiz` コマンドが設定ファイル (`*.conf`) を読んで読み込みます。

Rust 版は [juiz_examples_rust](https://github.com/OpenJUIZ/juiz_examples_rust)、Python 版は [juiz_examples_python](https://github.com/OpenJUIZ/juiz_examples_python)、C++ 版は [juiz_examples_cpp](https://github.com/OpenJUIZ/juiz_examples_cpp)、Haskell 版は [juiz_examples_haskell](https://github.com/OpenJUIZ/juiz_examples_haskell) にあります。

Zig は juiz 0.3.3 から使えます。

## しくみ

Zig のプラグインは、juiz の Zig 向けライブラリ zigjuiz (juiz の `bindings/zigjuiz`、`@import("juiz")`) で書き、juiz_sdk の共有ライブラリ `libjuiz_sdk` とリンクします。
zigjuiz は Zig の関数から juiz が探す C の関数を comptime に作るので、Zig のランタイムのようなものはプラグインに入りません。

このリポジトリの [build.sh](build.sh) が次のことを行います。

1. GitHub から juiz のソースを `build/juiz` に取得する (libjuiz_sdk を取得するスクリプトを使うため)
2. `JUIZ_GIT_REF` の版の `libjuiz_sdk` のアーカイブを juiz の GitHub Releases から取得する (タグでない版を指定したときや、取得できなかったときは、ソースの juiz_sdk を `cargo build --release -p juiz_sdk` でビルドする)
3. `zig build` でサンプルをビルドし (zigjuiz は [build.zig.zon](build.zig.zon) に書いた juiz の Releases の `zigjuiz-<版>.tar.gz` を `zig build` が取得する)、プラグインと `libjuiz_sdk` を `build/plugins` に並べて置く。サンプル共通の型 (`types/geometry.jidl`) は、ビルドの中で `juiz idl -g zig` が作る

プラグインは zigjuiz の `installBundle` で置くので、rpath は自分と同じ場所 (`$ORIGIN`、macOS は `@loader_path`) だけです。`build/plugins` のファイルをそのまま `.juizapp` に入れられます。

## 必要なもの

- Linux、macOS、Windows (x86_64) のいずれか。Windows では Git Bash で `./build.sh` を実行し、Rust の MSVC ツールチェーンを使います
- **Zig 0.17.x** (zigjuiz が対応する Zig は 1 つの版に固定しています。違う版では build.sh と zigjuiz の build.zig がエラーにします)。https://ziglang.org/download/ から入れるか、`pip install ziglang==0.17.1` で入れて `ZIG="python3 -m ziglang"` を付けて実行します
- Rust (stable)。`juiz` コマンドのビルドに使います。インストールは https://rustup.rs/ を参照してください
- git
- Linux では Python の開発用ファイル (`juiz` コマンドのビルドに使います。Ubuntu なら `sudo apt install python3-dev`)
- データ型のサンプル (`typed_pose.conf`) の Python の Process は pyjuiz を使います

## 1. juiz コマンドをインストールする

```sh
cargo install juiz_app --version 0.4.0 --locked
pip install pyjuiz==0.4.0
```

`juiz` コマンドが `~/.cargo/bin` に入ります。

## 2. サンプルをビルドする

```sh
git clone https://github.com/OpenJUIZ/juiz_examples_zig.git
cd juiz_examples_zig
./build.sh
```

初回は juiz の取得と libjuiz_sdk のビルドに少し時間がかかります。ビルドしたプラグインは `build/plugins` に出力されます。設定ファイルは `./build/plugins` からプラグインを探すので、**リポジトリのルートで** `juiz` を実行してください。

手元に juiz のソースがある場合は、それを使うこともできます (`build/juiz` がそこへのリンクになります)。

```sh
JUIZ_SOURCE_DIR=/path/to/juiz ./build.sh
```

## 3. 動かしてみる

### Process: increment_process_zig

引数に 1 を足して返すだけの Process です ([process/increment_process_zig.zig](process/increment_process_zig.zig))。

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

引数は 1 つの struct で受けます。フィールドの名前・型・既定値が、そのままマニフェストの引数になり、`.args` に説明を書きます (説明の書き漏れはコンパイルエラー)。
関数が返した Zig のエラー (ここでは i64 の最大値に足したときの `error.Overflow`) は、juiz の呼び出しのエラーになります。エラーを返さない関数は `!` を付けなくてかまいません ([decrement_process_zig.zig](process/decrement_process_zig.zig))。

```sh
juiz -f increment_process.conf -d
```

`-d` を付けると HTTP ブローカー (8000 番ポート) を立ち上げて待機します (Ctrl+C で終了)。
別のターミナルから呼び出せます。

```sh
juiz process list
juiz process call "http://127.0.0.1:8000/process/increment0::increment_process_zig" '{"arg1": 3}' -p
# => CapsulePtr((value:Value(4), option: []))
```

`decrement_process.conf` も同じ使い方です (1 を引く Process)。

```sh
juiz -f decrement_process.conf -d
juiz process call "http://127.0.0.1:8000/process/decrement0::decrement_process_zig" '{"arg1": 3}' -p
# => CapsulePtr((value:Value(2), option: []))
```

### Process の接続: talker / listener

`talker_zig` の出力を `listener_zig` の引数 `arg1` に Push 接続し、実行コンテキスト (main_loop_ec) で 1Hz で `talker_zig` を動かします。

```sh
juiz -f talker_listener.conf -d
# talker_zig: Hello, Juiz!
# listener_zig: Hello, Juiz!
# ...
```

文字列は `[]const u8` で受け取り、そのまま返します ([process/talker_zig.zig](process/talker_zig.zig)、[process/listener_zig.zig](process/listener_zig.zig))。表示は `std.debug.print` (標準エラー) です。

### Container: example_container_zig

状態 (整数値) を持つ Container と、それを操作する ContainerProcess (`example_container_zig_increment`、`example_container_zig_get`) のサンプルです。
Container と ContainerProcess は別々の共有ライブラリになるので、状態の型 ([container/example_container_state.zig](container/example_container_state.zig)) を両方から `@import` します。zigjuiz は状態の型の名前などから作った目印で、渡された Container が期待する型かを確かめます (違えば `-1104` のエラーで、juiz は落ちません)。

Container を作る関数は、設定ファイルの `containers` に書いた値を引数で受け取ります。この例では `value: 10` を初期値にしています。

```zig
fn create(args: struct { value: i64 = 0 }) state.Counter {
    return .{ .value = args.value };
}

comptime {
    juiz.exportContainer(create, .{
        .type_name = "example_container_zig",
        .description = "Holds an integer value.",
        .args = .{ .value = "initial value" },
    });
}
```

ContainerProcess は、最初の引数 `self` で Container の状態を受け取ります。`self` を `*const` で受けると readonly の ContainerProcess になります ([example_container_zig_get.zig](container/example_container_zig_get.zig))。

```zig
fn increment(self: *state.Counter, args: struct { arg1: i64 = 1 }) !i64 {
    self.value = try std.math.add(i64, self.value, args.arg1);
    return self.value;
}

comptime {
    juiz.exportContainerProcess(increment, .{
        .type_name = "example_container_zig_increment",
        .container_type = "example_container_zig",
        .description = "Adds arg1 to the value of the container.",
        .args = .{ .arg1 = "value to be added" },
    });
}
```

```sh
juiz -f example_container.conf -d
```

別のターミナルから呼び出すたびに値が増えていきます。

```sh
juiz container-process call "http://127.0.0.1:8000/container_process/increment0::example_container_zig_increment:container0" '{"arg1": 5}' -p
# => CapsulePtr((value:Value(15), option: []))
juiz container-process call "http://127.0.0.1:8000/container_process/get0::example_container_zig_get:container0" '{}' -p
# => CapsulePtr((value:Value(15), option: []))
```

### Component: example_component_zig

1 つのライブラリに Process・Container・ContainerProcess をまとめて入れる Component のサンプルです ([component/example_component_zig.zig](component/example_component_zig.zig))。
各要素の関数を単体のときと同じように書き、`juiz.exportComponent` の `.parts` に並べます。型名の重なりや、Component に無い Container の ContainerProcess はコンパイルエラーになります。

```zig
comptime {
    juiz.exportComponent(.{
        .type_name = "example_component_zig",
        .parts = .{
            juiz.processPart(increment, .{ .type_name = "example_component_zig_increment", ... }),
            juiz.containerPart(createContainer, .{ .type_name = "example_component_zig_container", ... }),
            juiz.containerProcessPart(containerGet, .{ .type_name = "example_component_zig_container_get", .container_type = "example_component_zig_container" }),
            juiz.containerProcessPart(containerIncrement, .{ .type_name = "example_component_zig_container_increment", ... }),
        },
    });
}
```

```sh
juiz -f example_component.conf -d
juiz process call "http://127.0.0.1:8000/process/proc0::example_component_zig_increment" '{"arg1": 1}' -p
# => CapsulePtr((value:Value(2), option: []))
juiz container-process call "http://127.0.0.1:8000/container_process/increment0::example_component_zig_container_increment:container0" '{"arg1": 5}' -p
# => CapsulePtr((value:Value(105), option: []))
juiz container-process call "http://127.0.0.1:8000/container_process/get0::example_component_zig_container_get:container0" '{}' -p
# => CapsulePtr((value:Value(105), option: []))
```

### ネームスペース: 同じ構成を並べて動かす

ネームスペースを使うと、同じ名前の Process を 1 つの System に並べて置けます。ID はクラスの後ろ・名前の前にネームスペースが入った `http://127.0.0.1:8000/process/robot1/talker0::talker_zig` の形になります。

`namespace.conf` は `talker0` と `listener0` を `robot1` と `robot2` の 2 つのネームスペースに置き、Topic `chatter` でつなぎます。Topic 名もネームスペースの中で解決されるので、それぞれの `listener0` には同じネームスペースの `talker0` の出力だけが届きます。

```sh
juiz -f namespace.conf -d
# talker_zig: Hello from robot1
# listener_zig: Hello from robot1
# talker_zig: Hello from robot2
# listener_zig: Hello from robot2
juiz process list --long
juiz process call "http://127.0.0.1:8000/process/robot1/talker0::talker_zig" '{"message": "Hi"}' -p
# => CapsulePtr((value:Value("Hi"), option: []))
```

`--namespace` を付けると、設定ファイルの既定のネームスペースを置き換えて起動できます。2 つのターミナルで次のように起動すると、2 つ目は 1 つ目のサブシステムになります (8001 番ポートで待ち受け)。

```sh
juiz -f increment_process.conf --namespace robot1 -d
juiz -f increment_process.conf --namespace robot2 -d
juiz process call "http://127.0.0.1:8001/process/robot2/increment0::increment_process_zig" '{"arg1": 10}' -p
# => CapsulePtr((value:Value(11), option: []))
```

### データ型: 言語をまたいで同じ型を使う

Process の引数と戻り値に型を付けられます。型は IDL (JIDL) で書き、生成器 `juiz-idl` で各言語の型を作ります。
[types/geometry.jidl](types/geometry.jidl) は、Zig・Rust・Python・C++・Haskell のサンプルリポジトリで同じ中身にしてあり、どの言語で作っても型の指紋 (`@sha256:…`) が同じになります。

```text
namespace examples.geometry;

record Point2D { double x = 0.0; double y = 0.0; }
record Pose2D  { Point2D position = {"x": 0.0, "y": 0.0}; double theta = 0.0; string frame_id = "map"; }
record Twist2D { double linear = 0.0; double angular = 0.0; }
```

Zig の Process [process/pose_move_zig.zig](process/pose_move_zig.zig) (`pose_move_zig`) は、この型を引数と戻り値に使います。型は [build.zig](build.zig) の `juiz.addTypes` が `juiz-idl -g zig` で作り、`juiz_types` という名前のモジュールで読み込みます。

```zig
// build.zig
const types = juiz.addTypes(.{ .files = &.{b.path("types/geometry.jidl")} });
const lib = juiz.addPlugin(.{
    .name = "pose_move_zig",
    .root_source_file = b.path("process/pose_move_zig.zig"),
    .imports = &.{.{ .name = "juiz_types", .module = types }},
});
```

```zig
// process/pose_move_zig.zig
const geometry = @import("juiz_types").examples.geometry;

fn poseMove(args: struct { pose: geometry.Pose2D = .{}, twist: geometry.Twist2D = .{}, dt: f64 = 1 }) geometry.Pose2D { … }
```

`typed_pose.conf` では、Python の Process ([python/](python/)) が出した `Twist2D` を Zig の `pose_move_zig` が受け取り、`pose_move_zig` が出した `Pose2D` を Python の Process が受け取ります。先に Python の型を `gen/` に作ってから起動します。

```text
twist0 (Python, Twist2D) --Pull--> move0 (Zig, pose_move_zig) --Push--> print0 (Python, Pose2D を表示)
```

```sh
juiz idl -g python -o gen types/geometry.jidl
juiz -f typed_pose.conf -d
curl -X PATCH "http://127.0.0.1:8000/api/process/execute?identifier=core://core/process/move0::pose_move_zig" -H "Content-Type: application/json" -d '{}'
# => {"frame_id":"map","position":{"x":0.5,"y":0.0},"theta":0.0}
juiz process call "http://127.0.0.1:8000/process/move0::pose_move_zig" '{"pose": {"position": {"x": 1.0, "y": 2.0}}, "twist": {"linear": 1.0}, "dt": 2.0}' -p
# => CapsulePtr((value:Value({"frame_id":"map","position":{"x":3.0,"y":2.0},"theta":0.0}), option: []))
juiz type show examples.geometry.Twist2D
# // examples.geometry.Twist2D@sha256:115b9e0f…
# // used by: pose_move_zig, twist_python
```

`typed_mismatch.conf` は `Twist2D` を `Pose2D` の引数につなごうとする設定ファイルで、juiz は接続を作らずにエラーで終わります。

```sh
juiz -f typed_mismatch.conf -d
# ... Type examples.geometry.Twist2D@sha256:115b9e0f… cannot be read as examples.geometry.Pose2D@sha256:123b8c15… ...
```

### Transformations: 部品の位置関係を木にする

ロボットの部品 (台車・雲台・カメラ) を Container にし、部品同士のつながり (Transform) と基点 (Anchor) を設定ファイルに書くと、juiz が各部品の位置姿勢 (ContainerPose) を計算します。

```text
map (PeriodicExecutionAnchor, 10 Hz)    … 10 Hz で木をたどって位置姿勢を計算し直す
└─ odom (StaticAnchor)                  … map から (1, 2, 0) ずれている
   └─ base0 (台車 mobile_base_zig)       … move0 がオドメトリを juiz.setPose で書く
      └─ pantilt0 (雲台 pantilt_zig)     … 台車の (0.1, 0, 0.3) に付く。pan0 がパン角を書く
         └─ camera0 (カメラ camera_zig)  … 雲台の (0.05, 0, 0.02) に付く。Transform だけ
```

部品は [component/mobile_robot_zig.zig](component/mobile_robot_zig.zig) の 1 つの Component (`mobile_robot_zig`) です。ContainerProcess の中では、受け取った `self` を渡して `juiz.pose(self, "map")` で読み、`juiz.setPose(self, "odom", pose)` で書きます。

```zig
fn move(self: *MobileBase, ctx: juiz.Context, args: struct { vx: f64 = 0, omega: f64 = 0, dt: f64 = 1, reference: []const u8 = "odom" }) !juiz.Value {
    self.x += args.vx * @cos(self.theta) * args.dt;
    self.y += args.vx * @sin(self.theta) * args.dt;
    self.theta += args.omega * args.dt;
    const written = try juiz.setPose(self, args.reference, juiz.makePose2d(self.x, self.y, self.theta));
    return juiz.poseStampedToValue(ctx.allocator, written, args.reference);
}
```

カメラの `camera_zig_pose` は `self` を `*const Camera` で受けるので readonly です。readonly の中から `juiz.setPose` を呼ぶとコンパイルエラーになります。
`pose_listeners:` で、台車の位置姿勢が書かれたら Process `print0` (`pose_print_zig`) を呼ぶ Pose 通知も登録しています。

```sh
juiz -f transformations.conf -d
juiz container-process call "http://127.0.0.1:8000/container_process/move0::mobile_base_zig_move:base0" '{"vx": 1.0, "dt": 1.0}' -p
# juiz を起動した端末に: pose_print_zig: x=1.00 y=0.00 yaw=0.0deg (from odom)
juiz container-process call "http://127.0.0.1:8000/container_process/pan0::pantilt_zig_set_pan:pantilt0" '{"pan": 1.5707963267948966}' -p
juiz container pose camera0 --reference map
# => position: x=2.1, y=2.05, z=0.32
juiz anchor tree map
```

Container には 3D モデル (`models/` の .glb・.sdf・.stl) も付けてあり、管理画面 (`http://127.0.0.1:8000/ui`) の「3D」で木を立体で見られます。モデルは [scripts/make_models.py](scripts/make_models.py) で作り直せます。

#### System をまたぐ: transformations_map.conf と transformations_robot.conf

上の木を、地図 (`map`) の System (ポート 8000) と、台車・雲台・カメラの System (ポート 8001) に分けた版です。`map → odom` の Transform はロボットの System が持ち、地図の System の `map` の位置を写しとして取り込みます。

```sh
juiz -f transformations_map.conf -d
juiz -f transformations_robot.conf -d
juiz container-process call "http://127.0.0.1:8001/container_process/move0::mobile_base_zig_move:base0" '{"vx": 1.0, "dt": 1.0}' -p
juiz -s http://127.0.0.1:8001 container pose camera0 --reference map
juiz -s http://127.0.0.1:8001 transform list --long
# ... (remote: ok)
```

地図の System を止めると、ロボットの System は `timeout` (3 秒) の後に写しを消し、`transform list --long` が `(remote: lost)` になります。

### アプリを .juizapp で配る

`packages/talker_listener/` を、1 つのファイル (`.juizapp`、zip) にまとめて配れます。受け取った人は、Zig 無しに `juiz run` だけで動かせます。

```sh
python3 scripts/make_packages.py      # 先に ./build.sh でビルドしておく
# copied: libtalker_zig.so
# copied: liblistener_zig.so
# copied: libjuiz_sdk.so
# Packed talker_listener 0.1.0 (x86_64-unknown-linux-gnu; ... files) into .../dist/talker_listener-0.1.0-x86_64-unknown-linux-gnu.juizapp
juiz run dist/talker_listener-0.1.0-x86_64-unknown-linux-gnu.juizapp
# talker_zig: Hello, Juiz!
# listener_zig: Hello, Juiz!
```

Zig のプラグインが使うのは `libjuiz_sdk` だけなので、[scripts/make_packages.py](scripts/make_packages.py) は `build/plugins` のプラグインと `libjuiz_sdk` を `plugins/<この機械のターゲット>/` に写して `juiz pack --target <ターゲット>` を呼ぶだけです。
タグ (`v*`) を付けると、CI が Linux (x86_64)・macOS (arm64)・Windows (x86_64) で作った `.juizapp` をこのリポジトリの Releases に載せます。

## 構成

| パス | 内容 |
| --- | --- |
| `process/` | Process (入力と出力を持つ冪等な関数) のサンプル |
| `container/` | Container (状態を持つ) と ContainerProcess のサンプル |
| `component/` | 複数の要素を 1 つのライブラリにまとめた Component のサンプル (`mobile_robot_zig.zig` は Transformations の部品) |
| `types/` | 5 つのサンプルリポジトリで共通に使う型 (JIDL) |
| `python/` | データ型のサンプルで Zig の Process とつなぐ Python の Process |
| `build.zig` / `build.zig.zon` | 各サンプルをプラグインとして宣言する Zig のビルド |
| `build.sh` | juiz のソースと libjuiz_sdk を用意し、サンプルをビルドして `build/plugins` に置く |
| `models/` | Transformations のサンプルの部品の 3D モデル |
| `*.conf` | 各サンプルを動かすための juiz の設定ファイル |
| `packages/` | `.juizapp` にするアプリのマニフェストと設定ファイル |
| `scripts/make_packages.py` | ビルドしたプラグインを `packages/` のアプリに集め、`dist/` に `.juizapp` を作るスクリプト |
| `scripts/make_models.py` | `models/` の .glb と .stl を作るスクリプト |
| `tests/test_examples.py` | 上のサンプルを起動して呼び出し、結果を確かめるテスト (ビルドのあと `python3 tests/test_examples.py`)。CI でも実行する |

## 自分で書くときは

### このリポジトリに足す

`.zig` ファイルを作り、[build.zig](build.zig) の `plugins` に名前とパスを足します。
名前は設定ファイルに書く名前 (`process_factories` などのキー) と同じにしてください。juiz はその名前から `lib<名前>.so` (macOS では `lib<名前>.dylib`、Windows では `<名前>.dll`) を探します。
zigjuiz の書き方の詳細は juiz の [bindings/zigjuiz/README.md](https://github.com/OpenJUIZ/juiz/blob/main/bindings/zigjuiz/README.md) を参照してください。

### 自分のプロジェクトで使う

`juiz pkg create my_robot -b zig` で、build.zig・Component のソース・conf・`.juizapp` を作るスクリプトの入った雛形を作れます。
雛形は zigjuiz を juiz の Releases から `zig fetch` で取り込み、libjuiz_sdk を `juiz sdk install` で入れます。詳しくは公式サイトの [雛形から始める (juiz pkg)](https://openjuiz.github.io/ja/guides/pkg/) を見てください。
juiz 0.3.5 からは、雛形と一緒に型の設計文書 `juizdesign.yaml` もできます。先に設計文書を書いてから `juiz pkg create -d juizdesign.yaml -b zig` で雛形を作ることもできます([設計文書 (juizdesign.yaml)](https://openjuiz.github.io/ja/guides/pkg/#設計文書juizdesignyaml))。

## juiz の版について

`build.sh` が取得する juiz の版は `JUIZ_GIT_REF` で決まります。既定値は `v0.4.0` で、上の手順で同じ版を入れた `juiz` コマンドと組み合わせて使います。
別の版を使うときは、`juiz` コマンドを入れた版と合わせて指定し、[build.zig.zon](build.zig.zon) の zigjuiz も同じ版のアーカイブにしてください (`zig fetch --save=zigjuiz https://github.com/OpenJUIZ/juiz/releases/download/v<版>/zigjuiz-<版>.tar.gz`)。

```sh
JUIZ_GIT_REF=<タグかコミット> ./build.sh
```

| このリポジトリ | juiz | Zig |
| --- | --- | --- |
| いま | 0.4.0 | 0.17.x |

## ライセンス

このリポジトリのサンプルは、次のどちらかのライセンスを選んで利用できます(デュアルライセンス)。

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) または <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT License ([LICENSE-MIT](LICENSE-MIT) または <https://opensource.org/licenses/MIT>)

Licensed under either of Apache License, Version 2.0 or MIT license at your option.

### コントリビューション

明示的に別の意思表示をしない限り、このリポジトリに提出されたコントリビューションは、Apache-2.0 ライセンスの定義に従い、追加の条件なしに上記と同じデュアルライセンスで提供されるものとします。

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
