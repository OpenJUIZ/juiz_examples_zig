#!/usr/bin/env bash
# サンプルをビルドし、juiz が読み込む共有ライブラリを build/plugins に置く。
#
# Zig の機能要素は juiz の Zig 向けライブラリ zigjuiz (bindings/zigjuiz) を使って書き、
# juiz_sdk の共有ライブラリ (libjuiz_sdk.so / libjuiz_sdk.dylib / juiz_sdk.dll) とリンクする。
#
#   JUIZ_SOURCE_DIR を指定した場合: そのディレクトリの juiz のソースを使う
#   指定しない場合: GitHub から JUIZ_GIT_REF の版を build/juiz に取得する
#
# 1. juiz のソースを build/juiz に用意する (zigjuiz を使うため。build.zig.zon がそこを参照する)。
#    zigjuiz を初めて配る juiz の版が公開されたら、build.zig.zon を Releases のアーカイブ (zig fetch) に切り替え、
#    この手順は要らなくなる
# 2. libjuiz_sdk を用意する。JUIZ_GIT_REF がタグ (v<版>) なら、その版のアーカイブを juiz の
#    scripts/install-juiz-sdk.sh (Windows は install-juiz-sdk.ps1) で build/juiz_sdk_archive に取得する。
#    JUIZ_SOURCE_DIR を指定した場合、タグでない場合、JUIZ_SDK_FROM_SOURCE=1 の場合、アーカイブの取得に失敗した場合は、
#    ソースの juiz_sdk を cargo build --release -p juiz_sdk でビルドする
# 3. zig build でサンプルをビルドし、プラグインと libjuiz_sdk を build/plugins に並べて置く
#    (プラグインには自分と同じ場所から libjuiz_sdk を探す rpath だけが付く。build.zig を参照)。
#    型 (types/geometry.jidl) は zig build の中で juiz-idl -g zig が作る (juiz-idl が無ければ `juiz idl`)
#
# zig コマンドは Zig 0.17.x が要る。名前は環境変数 ZIG で変えられる (例: ZIG="python3 -m ziglang")。
set -euo pipefail

JUIZ_GIT_REPOSITORY="${JUIZ_GIT_REPOSITORY:-https://github.com/OpenJUIZ/juiz.git}"
# 使用する juiz の版 (タグかコミット)。juiz コマンドを入れた版と合わせる。
# zigjuiz を初めて配る版が公開されるまでは、juiz の main のコミットに固定する
JUIZ_GIT_REF="${JUIZ_GIT_REF:-5700911b1017e4e63f933e90a966c9352e9ece31}"
JUIZ_SOURCE_DIR="${JUIZ_SOURCE_DIR:-}"
JUIZ_SDK_FROM_SOURCE="${JUIZ_SDK_FROM_SOURCE:-}"
ZIG="${ZIG:-zig}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$root/build"
juiz_dir="$build_dir/juiz"

case "$(uname -s)" in
    Darwin) ext=dylib; prefix=lib ;;
    # Windows (Git Bash など): DLL は lib の付かない <名前>.dll
    MINGW* | MSYS* | CYGWIN*) ext=dll; prefix="" ;;
    *) ext=so; prefix=lib ;;
esac

# zig に渡すパス。Windows では C:/... の形にする
native_path() {
    if [[ "$ext" == dll ]]; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

if ! $ZIG version > /dev/null 2>&1; then
    echo "error: zig コマンド ($ZIG) がありません。Zig 0.17.x を入れてください (https://ziglang.org/download/)。" >&2
    echo "       pip install ziglang==0.17.1 で入れたときは ZIG=\"python3 -m ziglang\" ./build.sh で実行します。" >&2
    exit 1
fi
zig_version="$($ZIG version)"
if [[ "$zig_version" != 0.17.* ]]; then
    echo "error: Zig $zig_version では使えません。zigjuiz が対応する Zig は 0.17.x です。" >&2
    exit 1
fi

mkdir -p "$build_dir"

# 1. juiz のソース
if [[ -n "$JUIZ_SOURCE_DIR" ]]; then
    JUIZ_SOURCE_DIR="$(cd "$JUIZ_SOURCE_DIR" && pwd)"
    if [[ -L "$juiz_dir" || ! -e "$juiz_dir" ]]; then
        ln -sfn "$JUIZ_SOURCE_DIR" "$juiz_dir"
    else
        echo "error: $juiz_dir がすでにあります。JUIZ_SOURCE_DIR を使うときは消してから実行してください。" >&2
        exit 1
    fi
    echo "juiz のソース: $JUIZ_SOURCE_DIR"
else
    if [[ -L "$juiz_dir" ]]; then
        rm "$juiz_dir"
    fi
    if [[ "$(cat "$build_dir/juiz.ref" 2>/dev/null)" != "$JUIZ_GIT_REF" || ! -d "$juiz_dir" ]]; then
        echo "juiz $JUIZ_GIT_REF を $JUIZ_GIT_REPOSITORY から取得します"
        rm -rf "$juiz_dir"
        git init -q "$juiz_dir"
        git -C "$juiz_dir" fetch -q --depth 1 "$JUIZ_GIT_REPOSITORY" "$JUIZ_GIT_REF"
        git -C "$juiz_dir" checkout -q FETCH_HEAD
        echo "$JUIZ_GIT_REF" > "$build_dir/juiz.ref"
    fi
fi

if [[ ! -e "$juiz_dir/bindings/zigjuiz/build.zig" ]]; then
    echo "error: juiz の Zig 向けライブラリが見つかりません: $juiz_dir/bindings/zigjuiz" >&2
    echo "       zigjuiz が入っている版の juiz を指定してください。" >&2
    exit 1
fi

# 2. libjuiz_sdk。sdk_lib_dir は zigjuiz の -Djuiz-sdk-lib に渡すディレクトリ
# (Linux・macOS は libjuiz_sdk.so / .dylib、Windows はインポートライブラリ juiz_sdk.dll.lib のある所。
#  juiz_sdk.dll は同じ所か ../bin から zigjuiz が探す)
sdk_lib_dir=""
if [[ -z "$JUIZ_SOURCE_DIR" && -z "$JUIZ_SDK_FROM_SOURCE" && "$JUIZ_GIT_REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    sdk_archive_dir="$build_dir/juiz_sdk_archive/${JUIZ_GIT_REF#v}"
    if [[ "$ext" == dll ]]; then
        # PowerShell 7 から開いた Git Bash では PSModulePath が PowerShell 7 のものになっていて、Windows PowerShell 5.1 が
        # 標準のモジュールを読み込めないので、PSModulePath を外す
        if [[ -e "$sdk_archive_dir/bin/juiz_sdk.dll" ]] \
            || env -u PSModulePath powershell.exe -NoProfile -ExecutionPolicy Bypass \
                -File "$(cygpath -w "$juiz_dir/scripts/install-juiz-sdk.ps1")" "$JUIZ_GIT_REF" "$(cygpath -w "$sdk_archive_dir")"; then
            sdk_lib_dir="$sdk_archive_dir/lib"
        else
            echo "libjuiz_sdk のアーカイブを取得できなかったので、ソースからビルドします"
        fi
    elif [[ -e "$sdk_archive_dir/lib/libjuiz_sdk.$ext" ]] \
        || sh "$juiz_dir/scripts/install-juiz-sdk.sh" "$JUIZ_GIT_REF" "$sdk_archive_dir"; then
        sdk_lib_dir="$sdk_archive_dir/lib"
    else
        echo "libjuiz_sdk のアーカイブを取得できなかったので、ソースからビルドします"
    fi
fi
if [[ -z "$sdk_lib_dir" ]]; then
    cargo build --release -p juiz_sdk \
        --manifest-path "$juiz_dir/Cargo.toml" \
        --target-dir "$build_dir/juiz_sdk"
    sdk_lib_dir="$build_dir/juiz_sdk/release"
fi
if [[ ! -e "$sdk_lib_dir/${prefix}juiz_sdk.$ext" && ! -e "$sdk_lib_dir/../bin/juiz_sdk.dll" ]]; then
    echo "error: $sdk_lib_dir に libjuiz_sdk がありません" >&2
    exit 1
fi

# 3. サンプル。--release で ReleaseSafe (build.zig の preferred_optimize_mode)
cd "$root"
rm -rf "$build_dir/plugins"
idl_args=()
if [[ -n "${JUIZ_IDL:-}" ]]; then
    idl_args=("-Djuiz-idl=$(native_path "$JUIZ_IDL")")
fi
$ZIG build --release --prefix "$(native_path "$build_dir")" \
    -Djuiz-sdk-lib="$(native_path "$sdk_lib_dir")" ${idl_args[@]+"${idl_args[@]}"}

# juiz は設定ファイルに書いた名前 NAME から lib<NAME>.so (macOS では lib<NAME>.dylib、Windows では <NAME>.dll) を探す
for name in $(sed -n -E 's/^[[:space:]]*\.\{ \.name = "([a-z0-9_]+)".*/\1/p' build.zig); do
    if [[ ! -f "$build_dir/plugins/$prefix$name.$ext" ]]; then
        echo "error: $build_dir/plugins/$prefix$name.$ext がありません" >&2
        exit 1
    fi
done
echo "プラグインを $build_dir/plugins に置きました"
