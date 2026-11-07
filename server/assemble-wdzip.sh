#!/bin/bash
# 构建前准备：把 server/wd-parts 下的分卷合并还原成 server/wd.zip
#
# wd.zip 原包 322MB，超过 GitHub 100MB 单文件限制，故以 zip 分卷形式入库
# （wd-parts/wd.zip + wd.z01 + wd.z02 + ... 每卷 <100MB）。
# 构建镜像前跑本脚本合并；若 server/wd.zip 已存在则跳过。
#
# 用法：bash server/assemble-wdzip.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARTS="$HERE/wd-parts"
OUT="$HERE/wd.zip"

if [ -f "$OUT" ]; then
    echo "[assemble] server/wd.zip 已存在（$(du -h "$OUT" | cut -f1)），跳过合并"
    exit 0
fi

if [ ! -d "$PARTS" ]; then
    echo "[assemble] 错误：找不到 wd-parts 目录" >&2
    exit 1
fi
if [ ! -f "$PARTS/wd.zip" ]; then
    echo "[assemble] 错误：找不到分卷主文件 $PARTS/wd.zip" >&2
    exit 1
fi

echo "[assemble] 合并分卷 → server/wd.zip ..."
TMP="$(mktemp -d)"
cp "$PARTS"/wd.z* "$PARTS"/wd.zip "$TMP"/ 2>/dev/null || true

# zip -s 0 将分卷合并为单一 zip
( cd "$TMP" && zip -q -s 0 wd.zip --out merged.zip )
mv "$TMP/merged.zip" "$OUT"
rm -rf "$TMP"

echo "[assemble] 完成：$(du -h "$OUT" | cut -f1)"
echo "[assemble] 校验 zip 完整性 ..."
if unzip -t "$OUT" >/dev/null 2>&1; then
    echo "[assemble] OK"
else
    echo "[assemble] 错误：合并后的 zip 校验失败" >&2
    exit 1
fi
