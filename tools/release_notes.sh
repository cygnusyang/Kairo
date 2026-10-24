#!/usr/bin/env bash
# tools/release_notes.sh —— 从 CHANGELOG.md 抽取指定版本的发布说明。
#
# 用法: tools/release_notes.sh v0.8.3     # stdout = 「## v0.8.3」到下一个「## 」之前的正文
# 退出码: 0 = 找到；1 = 无该版本章节（调用方须显式处理，禁止静默发空说明）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "用法: $(basename "$0") <tag，如 v0.8.3>" >&2
  exit 2
fi
case "$TAG" in v*) ;; *) TAG="v$TAG" ;; esac

if [[ ! -f "$CHANGELOG" ]]; then
  echo "未找到 CHANGELOG.md: $CHANGELOG" >&2
  exit 1
fi

NOTES="$(awk -v t="$TAG" '
  index($0, "## " t) == 1 { found = 1; next }
  /^## / && found { exit }
  found { print }
' "$CHANGELOG")"

# 去掉首尾空行
NOTES="$(printf '%s' "$NOTES" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ -z "${NOTES// /}" ]]; then
  echo "CHANGELOG.md 中没有「## ${TAG}」章节" >&2
  exit 1
fi

printf '%s\n' "$NOTES"
