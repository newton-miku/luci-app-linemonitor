#!/bin/sh
echo "=== 汇总文件里有没有「已完整拼接」的整条消息 ==="
grep -c '已完整拼接' /tmp/smstrunsum.conf 2>/dev/null
echo "--- 最近一次转发的完整内容 ---"
tail -n 60 /tmp/smstrunsum.conf
echo
echo "=== 出现过哪些「已完整拼接」的条目 ==="
grep -n '已完整拼接\|只收到' /tmp/smstrunsum.conf
echo
echo "=== 日志里有没有推送成功记录 ==="
grep -n 'Feishu response\|StatusCode' /tmp/smstrun.log | tail -n 8
