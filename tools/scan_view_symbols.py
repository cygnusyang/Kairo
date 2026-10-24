#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""视图边界扫描辅助：剥掉注释与字符串字面量后再匹配核心模型符号。

为什么不能直接 grep：视图里的英文兜底文案（如 "Project"、"Set Project Start Date"）
会误命中 \bProject\b，把门禁变成「翻译得越多越红」。本脚本按行剥除 // 注释与
双引号字面量（含转义），保留行号后再匹配，输出格式与 grep 一致：文件:行:原文。

用法：python3 tools/scan_view_symbols.py <目录> <正则>
退出码：0 无命中；1 有命中；2 用法或路径错误。
"""
import os
import re
import sys

PATTERN = re.compile(r"\b(Project|TaskItem|KairoSession|exportProject)\b")


def strip_line(line: str) -> str:
    """去掉行注释与字符串字面量，保留其余代码用于匹配。"""
    # 先剥字符串（含转义），再剥行注释，避免引号里的 // 被误判
    without_strings = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return re.sub(r"//.*$", "", without_strings)


def main() -> int:
    if len(sys.argv) != 3:
        print("用法: scan_view_symbols.py <目录> <正则>", file=sys.stderr)
        return 2
    root, pattern = sys.argv[1], sys.argv[2]
    if not os.path.isdir(root):
        print("scan_view_symbols: 未找到目录：%s" % root, file=sys.stderr)
        return 2
    matcher = re.compile(pattern)
    hits = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    lines = handle.read().split("\n")
            except OSError:
                continue
            for index, line in enumerate(lines, 1):
                if matcher.search(strip_line(line)):
                    hits.append("%s:%d:%s" % (path, index, line.strip()))
    if hits:
        print("\n".join(hits))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
