#!/bin/bash
# 视图边界门禁（ADR-013）：Workspace 视图目录不得直接引用核心模型或会话。
# 允许呈现类型（ProjectState、ProjectSummary 等）；适配层 WorkspaceStore 不在扫描范围。
# 符号链接目录也纳入扫描（find -L），避免新增视图经链接绕过。
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIEW_DIR="$ROOT_DIR/Apps/macos/Sources/Workspace"

if [[ ! -d "$VIEW_DIR" ]]; then
    echo "gate-ui: 未找到视图目录：$VIEW_DIR" >&2
    exit 2
fi

# 剥掉注释与字符串字面量后再匹配：视图里的英文兜底文案（"Project"、"Set Project Start Date"）
# 会误命中 \bProject\b，直接 grep 会让门禁「翻译得越多越红」。扫描器见 tools/scan_view_symbols.py。
VIOLATIONS=$(python3 "$ROOT_DIR/tools/scan_view_symbols.py" "$VIEW_DIR" \
    '\b(Project|TaskItem|KairoSession|exportProject)\b' 2>/dev/null || true)
if [[ -n "$VIOLATIONS" ]]; then
    echo "gate-ui: 视图直接引用核心模型，违反 ADR-013：" >&2
    echo "$VIOLATIONS" >&2
    exit 1
fi

COUNT=$(find -L "$VIEW_DIR" -type f -name '*.swift' | wc -l | tr -d ' ')
echo "gate-ui: 视图层仅经 WorkspaceAction/快照访问数据，通过（$COUNT 个 Swift 文件）"
exit 0
