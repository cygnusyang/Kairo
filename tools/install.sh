#!/usr/bin/env bash
# 将 dist/Kairo.app 安装到 /Applications（可用 INSTALL_DIR 覆盖）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP_NAME="Kairo"
APP_SRC="$DIST_DIR/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_DST="$INSTALL_DIR/${APP_NAME}.app"
BUILD_FIRST=0

usage() {
  cat <<USAGE
用法: $(basename "$0") [选项]

选项:
  --build              安装前先执行 tools/build.sh（Release）
  --dir <path>         安装目录（默认: /Applications）
  -h, --help           显示帮助

环境变量:
  DIST_DIR             构建产物目录（默认: <仓库>/dist）
  INSTALL_DIR          同 --dir
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_FIRST=1
      shift
      ;;
    --dir)
      INSTALL_DIR="${2:?}"
      APP_DST="$INSTALL_DIR/${APP_NAME}.app"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD_FIRST" -eq 1 || ! -d "$APP_SRC" ]]; then
  if [[ ! -d "$APP_SRC" ]]; then
    echo "==> 未找到 ${APP_SRC}，先编译打包"
  else
    echo "==> --build：重新编译打包"
  fi
  bash "$ROOT/tools/build.sh"
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "安装失败：仍未找到 $APP_SRC" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

if [[ -d "$APP_DST" ]]; then
  echo "==> 移除旧版 $APP_DST"
  rm -rf "$APP_DST"
fi

echo "==> 复制到 $APP_DST"
cp -R "$APP_SRC" "$APP_DST"

# 刷新 Launch Services，便于识别 kairo:// 与 .kairo
if command -v lsregister >/dev/null 2>&1; then
  lsregister -f "$APP_DST" >/dev/null 2>&1 || true
elif [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DST" >/dev/null 2>&1 || true
fi

echo "==> 已安装: $APP_DST"
echo "    打开: open \"$APP_DST\""
