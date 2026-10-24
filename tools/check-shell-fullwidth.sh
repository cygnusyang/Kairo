#!/bin/bash
# 全角字符紧贴变量名的检查（#7）。
#
# macOS 自带的 /bin/bash 是 3.2：变量名后面紧跟全角标点时，全角字符会被并入
# 变量名（$TAG（ → 变量「TAG（」）。带 set -u 的脚本于是以
# 「TAG（: unbound variable」崩掉，退出码 127，看不到本来要打印的原因；
# 不带 set -u 则变量取空，打印出残缺文案。两种表现都会把错误信息本身吞掉。
#
# 正确写法一律用 ${{VAR}。本脚本扫这一种错误，避免同类问题在错误路径里潜伏。
#
# 用法: tools/check-shell-fullwidth.sh [路径...]
#   缺省扫描 tools/ Plugins/ .github/ 下的 .sh / .yml / .yaml；
#   传入路径（文件或目录）则只扫传入的路径，便于本地复现。
# 退出码: 0 通过；1 有违规；2 用法错误或输入缺失
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_PATHS=(tools Plugins .github)
TARGETS=()
if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=("${DEFAULT_PATHS[@]}")
fi

usage() {
    cat <<USAGE
用法: $(basename "$0") [路径...]

  不给路径时扫描 tools/ Plugins/ .github/ 下的 .sh / .yml / .yaml。
  退出码: 0 通过；1 有违规；2 用法错误或输入缺失
USAGE
}

for target in "${TARGETS[@]}"; do
    case "$target" in
        -h|--help)
            usage
            exit 0
            ;;
    esac
    if [[ ! -e "$target" ]]; then
        echo "check-shell-fullwidth: 路径不存在：$target" >&2
        exit 2
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "check-shell-fullwidth: 未找到 python3（Xcode 命令行工具自带）" >&2
    exit 2
fi

python3 - "$ROOT_DIR" "${TARGETS[@]}" <<'PY'
import os
import re
import sys

root = sys.argv[1]
targets = sys.argv[2:]

# $VAR 紧跟非 ASCII 字符：全角标点、中文都会破坏 bash 3.2 的变量名解析。
PATTERN = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]')
SUFFIXES = ('.sh', '.yml', '.yaml')


def iter_files(target):
    if os.path.isfile(target):
        yield target
        return
    for dirpath, dirnames, filenames in os.walk(target):
        dirnames[:] = sorted(d for d in dirnames if d not in ('.git', 'node_modules', '.build'))
        for name in sorted(filenames):
            if name.endswith(SUFFIXES):
                yield os.path.join(dirpath, name)


hits = []
checked = 0
for target in targets:
    for path in iter_files(target):
        if not path.endswith(SUFFIXES):
            continue
        checked += 1
        rel = os.path.relpath(path, root) if path.startswith(root + os.sep) else path
        try:
            with open(path, encoding='utf-8', errors='replace') as handle:
                for number, line in enumerate(handle, 1):
                    if line.lstrip().startswith('#'):
                        continue
                    for match in PATTERN.finditer(line):
                        hits.append((rel, number, match.group(0), line.strip()))
        except OSError as error:
            print('check-shell-fullwidth: 无法读取 %s：%s' % (rel, error), file=sys.stderr)
            sys.exit(2)

if hits:
    print('check-shell-fullwidth: %d 个文件里发现 %d 处变量紧贴全角字符（bash 3.2 会把全角并入变量名）：'
          % (checked, len(hits)), file=sys.stderr)
    for rel, number, snippet, line in hits:
        print('  %s:%d  变量片段: %s' % (rel, number, snippet), file=sys.stderr)
        print('      %s' % line, file=sys.stderr)
    print('check-shell-fullwidth: 一律写 ${VAR}，不要写 $VAR 直接接全角或中文', file=sys.stderr)
    sys.exit(1)

print('check-shell-fullwidth: %d 个脚本/工作流文件无变量紧贴全角字符，通过' % checked)
sys.exit(0)
PY
