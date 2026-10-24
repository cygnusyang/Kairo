#!/usr/bin/env bash
# tools/package.sh —— 生成发布产物：DMG（人装）+ OTA 载体 zip（ditto 保留签名与元数据）。
#
# 用法:
#   tools/package.sh v0.8.3              # 构建 App 并产出 dist/Kairo-v0.8.3.{dmg,zip}
#   tools/package.sh 0.8.3               # 版本号可省略 v
#   tools/package.sh v0.8.3 --skip-build # 复用已有 dist/Kairo.app
#   tools/package.sh v0.8.3 --out /tmp/x # 指定输出目录（默认 dist/）
#
# 输出（stdout 末两行，便于脚本取值）:
#   ZIP_SHA256=<hex>
#   DMG_SHA256=<hex>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<USAGE
用法: $(basename "$0") <版本号，如 v0.8.3> [选项]

选项:
  --skip-build     跳过构建，直接打包已有 dist/Kairo.app
  --out <dir>      产物输出目录（默认 dist/）
  -h, --help       显示帮助
USAGE
}

RAW_VERSION=""
OUT_DIR="$ROOT/dist"
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --out) OUT_DIR="${2:?缺少 --out 参数}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$RAW_VERSION" ]]; then echo "多余参数: $1" >&2; exit 2; fi
      RAW_VERSION="$1"; shift ;;
  esac
done

if [[ -z "$RAW_VERSION" ]]; then usage >&2; exit 2; fi
VERSION="${RAW_VERSION#v}"
TAG="v${VERSION}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "版本号格式应为 X.Y.Z（可带 v 前缀），收到: $RAW_VERSION" >&2
  exit 2
fi

APP="$ROOT/dist/Kairo.app"
mkdir -p "$OUT_DIR"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "==> 构建 Release 应用"
  bash "$ROOT/tools/build.sh"
fi

if [[ ! -d "$APP" ]]; then
  echo "未找到应用包: ${APP}（先跑 tools/build.sh，或去掉 --skip-build）" >&2
  exit 1
fi

# 版本一致性门禁：产物内的 CFBundleShortVersionString 必须等于要发的版本号，
# 否则会把旧版本装进新 tag 的附件里（v0.8.1 之前踩过版本号漏改）。
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "版本不一致：应用包为 ${BUILT_VERSION:-未知}，期望 $VERSION" >&2
  echo "先跑 tools/release.sh（会同步三处版本号），或手工改 tools/build.sh 后重新构建。" >&2
  exit 1
fi

ZIP="$OUT_DIR/Kairo-${TAG}.zip"
DMG="$OUT_DIR/Kairo-${TAG}.dmg"

echo "==> 打包 OTA 载体 zip → $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 打包 DMG → $DMG"
STAGING="$(mktemp -d)/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Kairo.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Kairo ${TAG}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

ZIP_SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
DMG_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo "==> 完成"
echo "    DMG: $DMG"
echo "    ZIP: $ZIP"
echo "ZIP_SHA256=$ZIP_SHA"
echo "DMG_SHA256=$DMG_SHA"
