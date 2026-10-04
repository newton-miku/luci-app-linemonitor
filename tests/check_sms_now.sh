#!/bin/sh
echo "=== 1) 进程 ==="
ps w | grep -E '[s]mstrun'
echo
echo "=== 2) 攒段缓冲（Python 侧，只在内存里；靠日志观察）==="
echo "=== 3) 最近 40 行日志 ==="
tail -n 40 /tmp/smstrun.log
echo
echo "=== 4) seen 基线 ==="
wc -l < /etc/smstrun-seen.conf
echo
echo "=== 5) /etc/resolv.conf 是否仍是 tailscale 接管 ==="
head -n 4 /etc/resolv.conf
echo
echo "=== 6) hosts 兜底条目 ==="
grep -c 'smstrun-feishu' /etc/hosts
