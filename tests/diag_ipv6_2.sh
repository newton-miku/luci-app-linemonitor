#!/bin/sh
# 第二轮：确认移动侧 v6 到底能不能通，以及正确的源地址
LAN6=$(ip -6 addr show br-lan | awk '/scope global/{print $2}' | head -1 | cut -d/ -f1)
echo "br-lan 全局地址 = $LAN6"
echo

echo "===== A. 用 LAN 全局地址做源，分别测电信/移动目标 ====="
for t in 2400:3200::1 2409:8080::8 240e:f:a::6; do
  echo "--- ping6 -I $LAN6 -> $t ---"
  ping6 -c 2 -W 2 -I "$LAN6" "$t" 2>&1 | tail -2
done

echo
echo "===== B. 查看 ip -6 route get（源地址选择）====="
for t in 2400:3200::1 2409:8080::8; do
  echo "--- $t ---"
  ip -6 route get "$t" 2>&1
  ip -6 route get "$t" from "$LAN6" 2>&1
done

echo
echo "===== C. eth1 的 DHCPv6 请求详情 ====="
echo "reqaddress / reqprefix 现状:"
uci get network.wan6.reqaddress 2>/dev/null
uci get network.wan6.reqprefix 2>/dev/null
echo "odhcp6c 在 eth1 上的实际进程:"
ps w | grep odhcp6c | grep eth1 | grep -v grep

echo
echo "===== D. eth1 是否收到 RA ====="
cat /proc/net/if_inet6
echo "--- ip -6 route show dev eth1 ---"
ip -6 route show dev eth1

echo
echo "===== E. 从 LAN 侧看：CPE(192.168.8.1) 的 v6 能力 ====="
echo "--- 有没有 CPE 下发的 v6 地址在别的接口 ---"
ip -6 addr show | grep -B2 'scope global'

echo
echo "===== F. 手动触发一次 wan6 重连并观察 ====="
ifup wan6 2>&1 | head -5
sleep 8
echo "--- 8 秒后 eth1 地址 ---"
ip -6 addr show eth1
echo "--- mwan3 最新日志 ---"
logread 2>/dev/null | grep -iE 'wan6|mwan3track' | tail -8

echo
echo "===== G. 用 eth1 的 PD 源地址直接测移动 DNS ====="
PD=$(ip -6 route show dev br-lan | awk '/proto kernel/{print $1; exit}')
echo "br-lan PD 路由 = $PD"
if [ -n "$LAN6" ]; then
  echo "--- traceroute6 到 2409:8080::8（最多 5 跳）---"
  traceroute6 -m 5 -w 2 -s "$LAN6" 2409:8080::8 2>&1 | head -8
fi
