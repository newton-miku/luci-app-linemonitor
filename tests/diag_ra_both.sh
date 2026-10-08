#!/bin/sh
# 双向抓包：上游（wan / pppoe-wan）有没有 RA，LAN（br-lan）有没有 RA 被中继进来
echo "=== 1) 上游 wan 的 RA（15 秒） ==="
timeout 15 tcpdump -i wan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | head -n 30

echo
echo "=== 2) 上游 pppoe-wan 的 RA（15 秒） ==="
timeout 15 tcpdump -i pppoe-wan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | head -n 30

echo
echo "=== 3) LAN br-lan 的 RA（20 秒） ==="
timeout 20 tcpdump -i br-lan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | head -n 30

echo
echo "=== 4) LAN br-lan 上的所有 ICMPv6（20 秒，含 RS） ==="
timeout 20 tcpdump -i br-lan -n 'icmp6' 2>&1 | head -n 30

echo
echo "=== 5) odhcpd 的 relay 相关配置全貌 ==="
uci show dhcp | grep -E 'ra|ndp|dhcpv6|master|relay' 

echo
echo "=== 6) odhcpd 是否在 br-lan 上监听（socket 检查） ==="
netstat -lnp 2>/dev/null | grep -i dhcp || ss -lnp 2>/dev/null | grep -i dhcp || echo "(no netstat/ss)"

echo
echo "=== 7) odhcpd 启动参数 ==="
cat /etc/init.d/odhcpd 2>/dev/null | grep -E 'ra|relay|start|PROG|ARGS' | head -n 20

echo
echo "=== 8) relay 模式的 master 是哪条上游（odhcpd 日志） ==="
logread | grep -i odhcpd | grep -iE 'relay|master|learn|prefix' | tail -n 20

echo
echo "=== 9) 当前 br-lan 的 v6 地址与状态 ==="
ip -6 addr show br-lan | grep -E 'inet6|state'

echo
echo "=== 10) 手动尝试让客户端发 RS 看有无回应 ==="
echo "（这部分在路由器上做不了，跳过，改用本机验证）"
