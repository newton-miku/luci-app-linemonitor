#!/bin/sh
echo "=== seen 全部内容（带编号） ==="
awk '{printf "%3d  %s\n", NR, $0}' /etc/smstrun-seen.conf
echo
echo "行数: $(wc -l < /etc/smstrun-seen.conf)"
echo
echo "=== 单段键（值为 0 或单个数字，无逗号） ==="
awk 'NF>=2 && $2 !~ /,/ {printf "%3d  %s  %s\n", NR, $1, $2}' /etc/smstrun-seen.conf
