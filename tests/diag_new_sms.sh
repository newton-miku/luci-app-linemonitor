#!/bin/sh
echo "=== 1) 转发进程 ==="
ps w | grep -E '[s]mstrun'
echo
echo "=== 2) 手工跑一次 smstrun.sh，看它到底吐了什么 ==="
echo "--- 原始 AT 应答长度 ---"
sendat 1 AT+CMGL=4 2>/dev/null | wc -c
echo "--- smstrun.sh 输出（最近 40 行）---"
sh /usr/bin/smstrun.sh 2>&1 | tail -n 40
echo "--- 输出字节数 ---"
sh /usr/bin/smstrun.sh 2>/dev/null | wc -c
echo
echo "=== 3) 模组里 stat 状态（CMGL=4 带 stat）==="
sendat 1 AT+CMGL=4 2>/dev/null | grep -E '^\+CMGL:' | tail -n 6
echo
echo "=== 4) seen 基线内容 ==="
cat /etc/smstrun-seen.conf
echo
echo "=== 5) 日志最近 20 行 ==="
tail -n 20 /tmp/smstrun.log
