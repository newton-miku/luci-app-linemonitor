#!/bin/sh
echo "=== all_entry 原始前 3 行（完整，不截断） ==="
head -3 /sys/kernel/debug/hnat/all_entry
echo
echo "=== all_entry 原始行数 ==="
wc -l < /sys/kernel/debug/hnat/all_entry
echo
echo "=== hnat_entry 原始全部 ==="
cat /sys/kernel/debug/hnat/hnat_entry
echo
echo "=== all_entry 里带 index= 的行数 / state 分布 ==="
grep -c 'index=' /sys/kernel/debug/hnat/all_entry
grep -o 'state=[A-Z]*' /sys/kernel/debug/hnat/all_entry | sort | uniq -c
echo
echo "=== 饱和 conntrack 检查：bytes=2147483647 的行数 ==="
grep -c 'bytes=2147483647' /proc/net/nf_conntrack
echo
echo "=== 抽样：某个已饱和流的 5 秒增量（验证 b2 是否真的不动） ==="
for i in 1 2; do
  grep '192.168.66.21:5710' /proc/net/nf_conntrack | sed 's/.*mark=/mark=/'
  sleep 5
done