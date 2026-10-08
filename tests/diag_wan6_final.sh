#!/bin/sh
# 最后一轮：确认 CPE 侧的 v6 能力，以及改 reqaddress=force 是否有用
echo "===== 1. CPE 管理页可达性（从路由器）====="
ping -c 2 -W 2 203.0.113.1 2>&1 | tail -2
echo "--- HTTP 探测 ---"
(echo -e "GET / HTTP/1.0\r\nHost: 203.0.113.1\r\n\r\n"; sleep 3) | nc 203.0.113.1 80 2>&1 | head -c 400
echo

echo "===== 2. wan 的原始 v6 邻居与 RA 情况 ====="
echo "--- 有没有 RA 守护/路由宣告 ---"
ip -6 neigh show dev wan
echo "--- 直接听 5 秒 RA（只统计，不显示内容）---"
tcpdump -i wan -n -c 3 'icmp6 and ip6[40]==134' 2>&1 | tail -3

echo
echo "===== 3. 试 reqaddress=force 看 CPE 给不给地址 ====="
uci set network.wan6.reqaddress='force'
uci commit network
ifdown wan6; sleep 2; ifup wan6; sleep 10
echo "--- 结果 ipv6-address ---"
ifstatus wan6 | jsonfilter -e '@["ipv6-address"]' 2>/dev/null
ifstatus wan6 | grep -A4 '"ipv6-address"'
echo "--- 结果 ipv6-prefix ---"
ifstatus wan6 | grep -A5 '"ipv6-prefix"'

echo
echo "===== 4. 回滚 reqaddress=try ====="
uci set network.wan6.reqaddress='try'
uci commit network
ifdown wan6; sleep 2; ifup wan6; sleep 6
uci show network.wan6
echo "已回滚"

echo
echo "===== 5. CPE 到底宣告了什么（抓 DHCPv6 报文）====="
tcpdump -i wan -n -c 8 -vv 'udp port 546 or udp port 547' 2>&1 | head -30 &
TDPID=$!
sleep 2
ifdown wan6; sleep 1; ifup wan6
sleep 10
kill $TDPID 2>/dev/null
