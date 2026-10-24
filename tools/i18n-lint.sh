#!/bin/bash
# 多语言门禁（F-0711，docs/features/06-localization.md §3 / §8 / §13）。
#
# 三项检查：
#   (a) Apps/macos/Sources 出现白名单外中文字符串字面量（注释内的中文不算）
#   (b) KairoCore / KairoCommands / KairoPresentation 出现 Bundle.module（ADR-004 / ADR-013）
#   (c) en 与 zh-Hans 两份 .lproj 的键集合与占位符一致
#
# 没有「跳过」模式：缺输入就失败。CI 用 --require-catalog，连 Catalog 源文件是否存在
# 一并要求，避免「Catalog 没交付 → 键检查静默失效」的假绿。
#
# 用法: tools/i18n-lint.sh [--lproj-dir <dir>] [--require-catalog] [--catalog <路径>] [--write-whitelist]
#   --lproj-dir <dir>    检查 (c) 的 .lproj 目录，缺省 dist/Kairo.app/Contents/Resources
#   --require-catalog    同时要求 Catalog 源文件存在（CI 用），缺失即失败
#   --catalog <路径>     Catalog 源文件路径，缺省 Apps/macos/Resources/Localizable.xcstrings
#   --write-whitelist    按当前代码重写 tools/i18n-whitelist.txt 后退出
#   --fail-if-whitelist-nonempty
#                        白名单仍有条目即判失败（发布闸门，由 tools/release.sh 调用；
#                        不接 CI 常跑——开发期白名单必然非空）
# 退出码: 0 通过；1 违规；2 用法错误或输入缺失
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Apps/macos/Sources"
WHITELIST="$ROOT_DIR/tools/i18n-whitelist.txt"
LPROJ_DIR="$ROOT_DIR/dist/Kairo.app/Contents/Resources"
CATALOG="$ROOT_DIR/Apps/macos/Resources/Localizable.xcstrings"
REQUIRE_CATALOG=0
WRITE_WHITELIST=0
FAIL_ON_NONEMPTY=0
LAYER_DIRS=(
    "$ROOT_DIR/Sources/KairoCore"
    "$ROOT_DIR/Sources/KairoCommands"
    "$ROOT_DIR/Sources/KairoPresentation"
)

usage() {
    cat <<USAGE
用法: $(basename "$0") [选项]

选项:
  --lproj-dir <dir>    检查 (c) 的 .lproj 目录（缺省 dist/Kairo.app/Contents/Resources）
  --require-catalog    要求 Catalog 源文件存在（缺省 Apps/macos/Resources/Localizable.xcstrings）
  --catalog <路径>     Catalog 源文件路径
  --write-whitelist    按当前代码重写 tools/i18n-whitelist.txt 后退出
  --fail-if-whitelist-nonempty
                       白名单仍有条目即失败（发布闸门，release.sh 专用）
  -h, --help           显示帮助

本脚本没有「跳过检查 (c)」的开关：缺 .lproj 就是失败，退出码 2。
退出码: 0 通过；1 违规；2 用法错误或输入缺失
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lproj-dir)
            if [[ $# -lt 2 ]]; then
                echo "i18n-lint: --lproj-dir 需要一个目录参数" >&2
                exit 2
            fi
            LPROJ_DIR="$2"
            shift 2
            ;;
        --catalog)
            if [[ $# -lt 2 ]]; then
                echo "i18n-lint: --catalog 需要一个文件参数" >&2
                exit 2
            fi
            CATALOG="$2"
            shift 2
            ;;
        --require-catalog)
            REQUIRE_CATALOG=1
            shift
            ;;
        --write-whitelist)
            WRITE_WHITELIST=1
            shift
            ;;
        --fail-if-whitelist-nonempty)
            FAIL_ON_NONEMPTY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "i18n-lint: 未知参数: $1（本脚本没有 --skip-catalog：缺 .lproj 即失败）" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "i18n-lint: 未找到视图源码目录：$SOURCE_DIR" >&2
    exit 2
fi
for DIR in "${LAYER_DIRS[@]}"; do
    if [[ ! -d "$DIR" ]]; then
        echo "i18n-lint: 未找到分层目录：$DIR" >&2
        exit 2
    fi
done
if [[ "$WRITE_WHITELIST" -eq 0 && ! -f "$WHITELIST" ]]; then
    echo "i18n-lint: 未找到白名单：${WHITELIST}（先用 --write-whitelist 生成）" >&2
    exit 2
fi

if [[ "$WRITE_WHITELIST" -eq 0 ]]; then
    if [[ "$REQUIRE_CATALOG" -eq 1 && ! -f "$CATALOG" ]]; then
        echo "i18n-lint: 缺少 Catalog 源文件：$CATALOG" >&2
        echo "i18n-lint: 键与占位符无法校验；Catalog 由 F-0705 交付，未合入前本步骤保持失败（不以跳过代替）" >&2
        exit 2
    fi
    for LANG_ID in en zh-Hans; do
        if [[ ! -d "$LPROJ_DIR/${LANG_ID}.lproj" ]]; then
            echo "i18n-lint: 缺少 $LPROJ_DIR/${LANG_ID}.lproj" >&2
            echo "i18n-lint: 先运行 tools/i18n-compile.sh <目录> 再传入 --lproj-dir" >&2
            exit 2
        fi
    done
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "i18n-lint: 未找到 python3（Xcode 命令行工具自带；CI 的 macos-14 runner 亦有）" >&2
    exit 2
fi
if ! command -v plutil >/dev/null 2>&1; then
    echo "i18n-lint: 未找到 plutil" >&2
    exit 2
fi

python3 - "$ROOT_DIR" "$SOURCE_DIR" "$WHITELIST" "$LPROJ_DIR" "$WRITE_WHITELIST" "$FAIL_ON_NONEMPTY" "${LAYER_DIRS[@]}" <<'PY'
import json
import os
import re
import subprocess
import sys

root, source_dir, whitelist_path, lproj_dir = sys.argv[1:5]
write_whitelist = sys.argv[5] == '1'
fail_on_nonempty = sys.argv[6] == '1'
layer_dirs = sys.argv[7:]

CJK = re.compile('[\u2e80-\u2fff\u3000-\u303f\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]')
PLURAL_CATEGORIES = {'zero', 'one', 'two', 'few', 'many', 'other'}
PLACEHOLDER = re.compile(r'%(?:(\d+)\$)?[-+ #0]*[0-9.*]*(?:hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfFeEgGcsSip])')

violations = []
notes = []


def fail_input(message):
    print('i18n-lint: ' + message, file=sys.stderr)
    sys.exit(2)


def read_text(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def strip_comments(source):
    """去掉 // 与 /* */（Swift 块注释可嵌套），字符串字面量原样保留。"""
    out = []
    i, n = 0, len(source)
    state = None
    depth = 0
    while i < n:
        c = source[i]
        nxt = source[i + 1] if i + 1 < n else ''
        if state is None:
            if c == '/' and nxt == '/':
                state = 'line'
                i += 2
                continue
            if c == '/' and nxt == '*':
                state = 'block'
                depth = 1
                i += 2
                continue
            if source.startswith('"""', i):
                state = 'multiline'
                out.append('"""')
                i += 3
                continue
            if c == '"':
                state = 'string'
                out.append(c)
                i += 1
                continue
            out.append(c)
            i += 1
            continue
        if state == 'line':
            if c == '\n':
                state = None
                out.append(c)
            i += 1
            continue
        if state == 'block':
            if c == '*' and nxt == '/':
                depth -= 1
                i += 2
                state = None if depth == 0 else 'block'
                continue
            if c == '/' and nxt == '*':
                depth += 1
                i += 2
                continue
            if c == '\n':
                out.append(c)
            i += 1
            continue
        if state == 'string':
            if c == '\\':
                out.append(source[i:i + 2])
                i += 2
                continue
            if c == '"':
                state = None
            out.append(c)
            i += 1
            continue
        if state == 'multiline':
            if c == '\\':
                out.append(source[i:i + 2])
                i += 2
                continue
            if source.startswith('"""', i):
                state = None
                out.append('"""')
                i += 3
                continue
            out.append(c)
            i += 1
            continue
    return ''.join(out)


def string_literals(text):
    """返回 [(行号, 字面量原文)]；多行字面量的换行以 \n 表示，用于白名单比对。"""
    literals = []
    i, n = 0, len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if text.startswith('"""', i):
            end = text.find('"""', i + 3)
            if end < 0:
                break
            body = text[i + 3:end]
            literals.append((line, body.replace('\n', '\\n')))
            line += body.count('\n')
            i = end + 3
            continue
        if c == '"':
            j = i + 1
            buffer = []
            while j < n:
                if text[j] == '\\':
                    buffer.append(text[j:j + 2])
                    j += 2
                    continue
                if text[j] == '"' or text[j] == '\n':
                    break
                buffer.append(text[j])
                j += 1
            literals.append((line, ''.join(buffer)))
            i = j + 1
            continue
        i += 1
    return literals


def collect_view_literals():
    found = {}
    for dirpath, _, filenames in os.walk(source_dir):
        for name in sorted(filenames):
            if not name.endswith('.swift'):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            for line, literal in string_literals(strip_comments(read_text(path))):
                if CJK.search(literal):
                    found.setdefault(rel, {})
                    if literal not in found[rel]:
                        found[rel][literal] = line
    return found


def load_whitelist(path):
    entries = {}
    with open(path, encoding='utf-8') as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            if '\t' not in line:
                fail_input('%s:%d 格式错误，应为「路径<TAB>字面量」' % (path, number))
            rel, literal = line.split('\t', 1)
            entries.setdefault(rel, set()).add(literal)
    return entries


def write_whitelist_file(path, found):
    # 白名单为空时不写空行：让「grep -vc "^#" == 0」这类外部判据在清零后成立。
    lines = [
        '# i18n-lint 白名单（F-0711）。格式：<仓库相对路径><TAB><Swift 字符串字面量原文>',
        '# 仅用于记录迁移基线：新出现的硬编码中文一律失败；已清理的条目会作为提示列出。',
        '# v0.9.0 发布前本文件应为空（视图层零中文），由 F-0705 收口时重新生成。',
        '# 重新生成：bash tools/i18n-lint.sh --write-whitelist',
        '# 判据：不要用 grep -vc "^#"（旧格式末尾有空行，恒差 1）；用'
        '#   --fail-if-whitelist-nonempty 的退出码，或 grep -v "^#" … | grep -c "[^[:space:]]"。',
    ]
    rows = []
    total = 0
    for rel in sorted(found):
        for literal in sorted(found[rel]):
            rows.append('%s\t%s' % (rel, literal))
            total += 1
    if rows:
        lines.append('')
        lines.extend(rows)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines) + '\n')
    return total


def check_bundle_module():
    for layer in layer_dirs:
        for dirpath, _, filenames in os.walk(layer):
            for name in sorted(filenames):
                if not name.endswith('.swift'):
                    continue
                path = os.path.join(dirpath, name)
                for number, line in enumerate(read_text(path).split('\n'), 1):
                    if 'Bundle.module' in line:
                        rel = os.path.relpath(path, root)
                        violations.append('%s:%d: 分层不得引入本地化资源（Bundle.module），违反 ADR-004 / ADR-013' % (rel, number))


def load_plist(path):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', path],
                            capture_output=True, text=True)
    if result.returncode != 0:
        fail_input('无法解析 %s：%s' % (path, result.stderr.strip()))
    body = result.stdout.strip()
    return json.loads(body) if body else {}


def placeholders(value):
    return sorted('%s:%s' % (m.group(1) or '', m.group(2)) for m in PLACEHOLDER.finditer(value))


def plural_categories(entry):
    """stringsdict 每个键的值是 {NSStringLocalizedFormatKey, <变量名>: {分类: 文案}}，
    分类表在变量名那一层，不在键的直接子级。"""
    for name, value in entry.items():
        if name == 'NSStringLocalizedFormatKey':
            continue
        if isinstance(value, dict) and any(category in value for category in PLURAL_CATEGORIES):
            return {category: value[category] for category in value if category in PLURAL_CATEGORIES}
    return {}


def compare_table(en, zh, language_label, plural):
    en_keys, zh_keys = set(en), set(zh)
    for key in sorted(en_keys - zh_keys):
        violations.append('键缺少 zh-Hans 译文：%s（%s）' % (key, language_label))
    for key in sorted(zh_keys - en_keys):
        violations.append('键只在 zh-Hans 存在：%s（%s）' % (key, language_label))
    for key in sorted(en_keys & zh_keys):
        if plural:
            en_cats, zh_cats = plural_categories(en[key]), plural_categories(zh[key])
            if 'other' not in en_cats or 'other' not in zh_cats:
                violations.append('复数缺少 other 分类：%s（%s）' % (key, language_label))
                continue
            en_ph, zh_ph = placeholders(en_cats['other']), placeholders(zh_cats['other'])
        else:
            en_ph, zh_ph = placeholders(en[key]), placeholders(zh[key])
        if en_ph != zh_ph:
            violations.append('占位符不一致：%s（%s）en=%s zh-Hans=%s'
                              % (key, language_label, ','.join(en_ph) or '无', ','.join(zh_ph) or '无'))


def check_catalog():
    en_dir = os.path.join(lproj_dir, 'en.lproj')
    zh_dir = os.path.join(lproj_dir, 'zh-Hans.lproj')
    key_total = 0
    clean = True
    for filename, plural in (('Localizable.strings', False), ('Localizable.stringsdict', True)):
        en_path, zh_path = os.path.join(en_dir, filename), os.path.join(zh_dir, filename)
        en_exists, zh_exists = os.path.exists(en_path), os.path.exists(zh_path)
        if not en_exists and not zh_exists:
            continue
        if en_exists != zh_exists:
            violations.append('%s 只在单侧存在（en=%s，zh-Hans=%s）'
                              % (filename, en_exists, zh_exists))
            clean = False
            continue
        en_table, zh_table = load_plist(en_path), load_plist(zh_path)
        key_total += len(en_table)
        before_table = len(violations)
        compare_table(en_table, zh_table, filename, plural)
        if len(violations) != before_table:
            clean = False
    if key_total == 0:
        violations.append('%s 下没有 Localizable.strings / Localizable.stringsdict（Catalog 未编译进包，或 Catalog 文件名不是 Localizable.xcstrings）' % lproj_dir)
    elif clean:
        print('i18n-lint: (c) 键与占位符一致（%d 个键 / %s）' % (key_total, lproj_dir))


found = collect_view_literals()

if write_whitelist:
    total = write_whitelist_file(whitelist_path, found)
    print('i18n-lint: 已写入 %s（%d 条）' % (whitelist_path, total))
    sys.exit(0)

whitelist = load_whitelist(whitelist_path)
whitelist_total = sum(len(literals) for literals in whitelist.values())
if fail_on_nonempty and whitelist_total:
    violations.append('发布闸门：tools/i18n-whitelist.txt 仍有 %d 条未清理的中文'
                      '（视图层零中文是 v0.9.0 发布判据，见 06-localization §11 判据 1；'
                      'F-0705 收口时清零并重跑 --write-whitelist）' % whitelist_total)
allowed = 0
unregistered = 0
for rel in sorted(found):
    for literal, line in sorted(found[rel].items(), key=lambda item: item[1]):
        if literal in whitelist.get(rel, set()):
            allowed += 1
            continue
        unregistered += 1
        violations.append('%s:%d: 未登记的中文字符串字面量：%s' % (rel, line, literal))
stale = 0
for rel in sorted(whitelist):
    for literal in sorted(whitelist[rel]):
        if literal not in found.get(rel, {}):
            stale += 1
if stale:
    notes.append('白名单有 %d 条已清理（可运行 --write-whitelist 收口）' % stale)
if unregistered:
    print('i18n-lint: (a) 未登记的中文字符串字面量 %d 条' % unregistered)
else:
    print('i18n-lint: (a) 白名单内中文 %d 条，无新增' % allowed)

before_layer_check = len(violations)
check_bundle_module()
if len(violations) == before_layer_check:
    print('i18n-lint: (b) KairoCore/KairoCommands/KairoPresentation 无 Bundle.module')

check_catalog()

for note in notes:
    print('i18n-lint: 提示：' + note)

if violations:
    print('i18n-lint: 发现 %d 处违规：' % len(violations), file=sys.stderr)
    for violation in violations:
        print('  ' + violation, file=sys.stderr)
    sys.exit(1)

print('i18n-lint: 通过')
sys.exit(0)
PY
