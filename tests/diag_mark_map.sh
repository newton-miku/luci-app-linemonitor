#!/bin/sh
echo "=== ip rule (v4) ==="
ip rule show

echo
echo "=== mwan3 uci 接口与 id ==="
uci show mwan3 2>/dev/null | grep -E 'network=|\.id=|\.device=|track_ip'

echo
echo "=== 各表里出现的 dev（v4 / v6） ==="
for t in 1 2 3 4; do
  echo "-- table $t v4 dev:"; ip route show table "$t" 2>/dev/null | grep -oE 'dev [a-zA-Z0-9._-]+' | sort -u
  echo "-- table $t v6 dev:"; ip -6 route show table "$t" 2>/dev/null | grep -oE 'dev [a-zA-Z0-9._-]+' | sort -u
done

echo
echo "=== v4 路由查找（确认 mark 归属） ==="
for m in 256 512 768 1024; do
  printf 'mark %-5s -> ' "$m"
  ip route get 1.2.4.8 mark $m 2>&1 | head -1
done

echo
echo "=== 当前 conntrack 里的 mark 分布（前 20 条 TCP/UDP） ==="
grep -oE 'mark=[0-9]+' /proc/net/nf_conntrack 2>/dev/null | sort | uniq -c | sort -rn | head -20
