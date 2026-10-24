#!/bin/bash
# 编译 String Catalog 为 .lproj（F-0700 主路径 B，见 docs/features/06-localization.md §7）。
#
# .xcstrings 只作源文件：SwiftPM 的 .process 资源只原样拷贝、不编译（E1），生成的
# resource bundle 也没有 Info.plist（E2），因此运行期只认 .app 内的 .lproj。
# 本脚本产出 en.lproj / zh-Hans.lproj，由 tools/build.sh 拷进 Contents/Resources。
#
# 用法: tools/i18n-compile.sh <输出目录> [Catalog 路径]
#   输出目录由本脚本独占（已存在则重建，避免上一次的语言目录残留）；
#   Catalog 缺省为 Apps/macos/Resources/Localizable.xcstrings。
# 退出码: 0 成功；1 编译未产出任何 .lproj；2 用法错误或输入缺失（Catalog / xcstringstool）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_CATALOG="$ROOT_DIR/Apps/macos/Resources/Localizable.xcstrings"

usage() {
    cat <<USAGE
用法: $(basename "$0") <输出目录> [Catalog 路径]

  <输出目录>       生成 <输出目录>/{lang}.lproj，已存在则重建
  [Catalog 路径]   .xcstrings 源文件，缺省 $DEFAULT_CATALOG
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 2
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

OUT_DIR="$1"
CATALOG="${2:-$DEFAULT_CATALOG}"

# 输出目录绝对化后拒绝根目录，避免 rm -r 落到 "/"
case "$OUT_DIR" in
    /*) ;;
    *) OUT_DIR="$PWD/$OUT_DIR" ;;
esac
OUT_DIR="${OUT_DIR%/}"
if [[ -z "$OUT_DIR" ]]; then
    echo "i18n-compile: 拒绝把 / 作为输出目录" >&2
    exit 2
fi

if [[ ! -f "$CATALOG" ]]; then
    echo "i18n-compile: 未找到 Catalog：$CATALOG" >&2
    echo "i18n-compile: Catalog 由 Apps/macos/Resources/Localizable.xcstrings 提供，缺失时不打包（§7 第 4 条）" >&2
    exit 2
fi

# 表名由文件名决定：Localizable.xcstrings → Localizable.strings，而运行期取词走
# Bundle.localizedString(forKey:value:table: nil)，只读 Localizable 表。改成别的
# 名字编译会得到 Foo.strings，界面静默显示英文兜底——直接拒绝。
CATALOG_NAME="$(basename "$CATALOG")"
if [[ "$CATALOG_NAME" != "Localizable.xcstrings" ]]; then
    echo "i18n-compile: Catalog 文件名必须是 Localizable.xcstrings，收到：$CATALOG_NAME" >&2
    echo "i18n-compile: xcstringstool 按文件名生成表名（Localizable.xcstrings → Localizable.strings），运行期只读 Localizable 表；改名的目录里请复制成 Localizable.xcstrings 再编译" >&2
    exit 2
fi

if ! command -v xcrun >/dev/null 2>&1; then
    echo "i18n-compile: 未找到 xcrun，需要安装 Xcode 命令行工具" >&2
    exit 2
fi
if ! xcrun --find xcstringstool >/dev/null 2>&1; then
    echo "i18n-compile: 未找到 xcstringstool（Xcode 15+ 自带）" >&2
    exit 2
fi

if [[ -e "$OUT_DIR" && ! -d "$OUT_DIR" ]]; then
    echo "i18n-compile: 输出目录已存在且不是目录：$OUT_DIR" >&2
    exit 2
fi

if [[ -d "$OUT_DIR" ]]; then
    rm -r "$OUT_DIR"
fi
if ! mkdir -p "$OUT_DIR"; then
    echo "i18n-compile: 无法创建输出目录：$OUT_DIR" >&2
    exit 2
fi

xcrun xcstringstool compile --output-directory "$OUT_DIR" "$CATALOG"

LANGS=$(find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type d -name '*.lproj' -exec basename {} .lproj \; | sort)
if [[ -z "$LANGS" ]]; then
    echo "i18n-compile: 编译未产出任何 .lproj：$CATALOG" >&2
    exit 1
fi

echo "i18n-compile: ${CATALOG} → ${OUT_DIR}（$(echo "$LANGS" | tr '\n' ' ' | sed 's/ $//')）"
