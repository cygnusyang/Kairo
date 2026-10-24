#!/bin/bash
# i18n-lint 门禁自测（F-0711）。用例只增不减——新增检查项时在此追加用例，不得改小。
# 现 25 例；其中「--require-catalog 齐全时三验全过」是 CI 判定「三项都验了」的基准。
#
# 每个用例自建临时仓库（mktemp -d 下），只依赖 tools/i18n-lint.sh 与
# tools/i18n-compile.sh 两个被测脚本，不读仓库源码树、不跑 swift、不动 .build。
# 用法: tools/i18n-lint-selftest.sh
# 退出码: 0 全部通过；1 有用例失败
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT_DIR/tools/i18n-lint.sh"
COMPILE="$ROOT_DIR/tools/i18n-compile.sh"
WORK="$(mktemp -d)"
PASS=0
FAIL=0
FAILURES=""
T=""
LAST_RC=0
LAST_OUT=""

pass() {
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILURES="${FAILURES}
  - $1"
    printf 'FAIL %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2" | sed 's/^/     /'
    fi
}

# 新用例：干净的临时仓库 + 最小基线（1 个普通键 + 1 个复数键 + 1 条中文）
new_tree() {
    T="$WORK/$1"
    mkdir -p "$T/tools" "$T/Apps/macos/Sources/Workspace" \
        "$T/Sources/KairoCore" "$T/Sources/KairoCommands" "$T/Sources/KairoPresentation" \
        "$T/lproj/en.lproj" "$T/lproj/zh-Hans.lproj"
    cp "$LINT" "$T/tools/i18n-lint.sh"
    cp "$COMPILE" "$T/tools/i18n-compile.sh"
    cat > "$T/lproj/en.lproj/Localizable.strings" <<'STR'
"column.status" = "Status";
STR
    cat > "$T/lproj/zh-Hans.lproj/Localizable.strings" <<'STR'
"column.status" = "状态";
STR
    cat > "$T/lproj/en.lproj/Localizable.stringsdict" <<'JSON'
{"palette.result.count": {"NSStringLocalizedFormatKey": "%#@value@", "value": {"one": "%1$ld task", "other": "%1$ld tasks", "NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "ld"}}}
JSON
    cat > "$T/lproj/zh-Hans.lproj/Localizable.stringsdict" <<'JSON'
{"palette.result.count": {"NSStringLocalizedFormatKey": "%#@value@", "value": {"other": "%1$ld 个任务", "NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "ld"}}}
JSON
    printf 'let status = "状态"\n' > "$T/Apps/macos/Sources/Workspace/Base.swift"
}

# 在 $T 下执行命令，记录退出码与输出
run() {
    LAST_OUT="$(cd "$T" && "$@" 2>&1)"
    LAST_RC=$?
}

expect() {
    local label="$1" want="$2" needle="${3:-}" ok=1
    [[ "$LAST_RC" -eq "$want" ]] || ok=0
    if [[ -n "$needle" ]] && ! printf '%s' "$LAST_OUT" | grep -qF -- "$needle"; then
        ok=0
    fi
    if [[ "$ok" -eq 1 ]]; then
        pass "$label"
    else
        fail "$label" "期望 exit=${want}，且含「${needle}」，实际 exit=${LAST_RC}
$(printf '%s' "$LAST_OUT" | sed -n '1,5p')"
    fi
}

# —— 用法与输入缺失 ——

new_tree no-whitelist
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "缺白名单 → 2" 2 "未找到白名单"

new_tree unknown-arg
run bash tools/i18n-lint.sh --lproj-dir lproj --nope
expect "未知参数 → 2" 2 "未知参数"

new_tree missing-value
run bash tools/i18n-lint.sh --lproj-dir
expect "--lproj-dir 缺参 → 2" 2 "需要一个目录参数"

new_tree help
run bash tools/i18n-lint.sh --help
expect "--help → 0" 0 "用法: i18n-lint.sh"

new_tree no-zh-lproj
run bash tools/i18n-lint.sh --write-whitelist
rm -r "$T/lproj/zh-Hans.lproj"
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "缺 zh-Hans.lproj → 2" 2 "缺少"

new_tree bad-whitelist
run bash tools/i18n-lint.sh --write-whitelist
printf 'no-tab-line\n' >> "$T/tools/i18n-whitelist.txt"
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "白名单格式错误 → 2" 2 "格式错误"

# —— 检查 (a)：硬编码中文 ——

new_tree baseline
run bash tools/i18n-lint.sh --write-whitelist
expect "--write-whitelist → 0" 0 "已写入"
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "基线内中文 → 0" 0 "无新增"

new_tree new-chinese
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/Apps/macos/Sources/Workspace/Added.swift" <<'SWIFT'
let a = "新加的中文"
SWIFT
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "未登记中文 → 1" 1 "未登记的中文字符串字面量：新加的中文"

new_tree comment-chinese
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/Apps/macos/Sources/Workspace/Comment.swift" <<'SWIFT'
// 行注释里的中文
/* 块注释 /* 嵌套 */ 仍是注释 */
let a = "Status"
SWIFT
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "注释内中文不报 → 0" 0 "无新增"

new_tree multiline-chinese
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/Apps/macos/Sources/Workspace/Multi.swift" <<'SWIFT'
let s = """
  多行中文
"""
SWIFT
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "多行字面量中文 → 1" 1 "Multi.swift:1: 未登记的中文字符串字面量"

new_tree stale-whitelist
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/tools/i18n-whitelist.txt" <<'WL'
Apps/macos/Sources/Gone.swift	已删除的中文
Apps/macos/Sources/Workspace/Base.swift	状态
WL
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "白名单过期条目只提示 → 0" 0 "已清理"

new_tree whitelist-idempotent
run bash tools/i18n-lint.sh --write-whitelist
cp "$T/tools/i18n-whitelist.txt" "$T/wl-first.txt"
run bash tools/i18n-lint.sh --write-whitelist
if cmp -s "$T/wl-first.txt" "$T/tools/i18n-whitelist.txt"; then
    pass "--write-whitelist 幂等 → 文件不变"
else
    fail "--write-whitelist 幂等 → 文件不变" "两次生成的 whitelist 不一致"
fi

# —— 检查 (b)：分层资源 ——

new_tree layer-bundle-module
run bash tools/i18n-lint.sh --write-whitelist
printf 'import Foundation\nlet b = Bundle.module\n' > "$T/Sources/KairoCore/Bad.swift"
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "分层 Bundle.module → 1" 1 "分层不得引入本地化资源"

# —— 检查 (c)：键集合与占位符 ——

new_tree missing-zh-key
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/lproj/en.lproj/Localizable.strings" <<'STR'
"column.status" = "Status";
"column.effort" = "Effort";
STR
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "zh 缺键 → 1" 1 "键缺少 zh-Hans 译文：column.effort"

new_tree extra-zh-key
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/lproj/zh-Hans.lproj/Localizable.strings" <<'STR'
"column.status" = "状态";
"column.extra" = "多余";
STR
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "只在 zh 的键 → 1" 1 "键只在 zh-Hans 存在：column.extra"

new_tree placeholder-type
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/lproj/zh-Hans.lproj/Localizable.stringsdict" <<'JSON'
{"palette.result.count": {"NSStringLocalizedFormatKey": "%#@value@", "value": {"other": "%1$@ 个任务"}}}
JSON
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "占位符类型不一致 → 1" 1 "占位符不一致：palette.result.count"

new_tree placeholder-count
run bash tools/i18n-lint.sh --write-whitelist
cat > "$T/lproj/zh-Hans.lproj/Localizable.stringsdict" <<'JSON'
{"palette.result.count": {"NSStringLocalizedFormatKey": "%#@value@", "value": {"other": "%1$ld 个任务 %2$@"}}}
JSON
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "复数占位符个数不一致 → 1" 1 "占位符不一致：palette.result.count"

new_tree empty-catalog
run bash tools/i18n-lint.sh --write-whitelist
find "$T/lproj" -name 'Localizable.strings*' -delete
run bash tools/i18n-lint.sh --lproj-dir lproj
expect "lproj 无 strings → 1" 1 "没有 Localizable.strings"

# —— 不假绿：没有跳过模式，CI 用 --require-catalog ——

new_tree skip-catalog-removed
run bash tools/i18n-lint.sh --write-whitelist
run bash tools/i18n-lint.sh --skip-catalog
expect "--skip-catalog 已移除 → 2" 2 "未知参数"

new_tree require-catalog-missing
run bash tools/i18n-lint.sh --write-whitelist
run bash tools/i18n-lint.sh --require-catalog --lproj-dir lproj
expect "--require-catalog 缺 Catalog → 2" 2 "缺少 Catalog 源文件"

new_tree require-catalog-ok
run bash tools/i18n-lint.sh --write-whitelist
mkdir -p "$T/Apps/macos/Resources"
cat > "$T/Apps/macos/Resources/Localizable.xcstrings" <<'JSON'
{"sourceLanguage": "en", "strings": {}, "version": "1.0"}
JSON
run bash tools/i18n-lint.sh --require-catalog --lproj-dir lproj
expect "--require-catalog 齐全时三验全过 → 0" 0 "(c) 键与占位符一致"

# —— i18n-compile.sh 的输入校验（不依赖 Xcode）——

new_tree compile-no-arg
run bash tools/i18n-compile.sh
expect "i18n-compile 无参数 → 2" 2 "用法"

new_tree compile-missing-catalog
run bash tools/i18n-compile.sh "$T/out" "$T/nope.xcstrings"
expect "i18n-compile 缺 Catalog → 2" 2 "未找到 Catalog"

new_tree compile-wrong-name
printf '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n' > "$T/Foo.xcstrings"
run bash tools/i18n-compile.sh "$T/out" "$T/Foo.xcstrings"
expect "i18n-compile 文件名非 Localizable → 2" 2 "文件名必须是 Localizable.xcstrings"

# —— 汇总 ——

TOTAL=$((PASS + FAIL))
printf '\n自测：%d/%d 通过\n' "$PASS" "$TOTAL"
if [[ "$FAIL" -ne 0 ]]; then
    printf '失败用例：%s\n' "$FAILURES"
    exit 1
fi
exit 0
