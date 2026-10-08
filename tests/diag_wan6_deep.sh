#!/bin/sh
# 深挖 wan6 为什么「没拿到地址」——看 DHCPv6 交互与 CPE 侧行为
echo "===== 1. wan 上的 RA 接收情况 ====="
echo "--- 内核 v6 参数 ---"
for f in accept_ra accept_ra_defrtr accept_ra_pinfo accept_ra_rtr_pref autoconf; do
  printf "  %-22s = %s\n" "$f" "$(cat /proc/sys/net/ipv6/conf/wan/$f 2>/dev/null)"
done
echo "--- wan 收到的 RA 缓存（ip -6 route show cache）---"
ip -6 route show dev wan table all 2>/dev/null

echo
echo "===== 2. odhcp6c 详细日志（重启 wan6 抓一次）====="
logread -f > /tmp/lm_log6.txt 2>&1 &
LOGPID=$!
sleep 1
ifdown wan6; sleep 2; ifup wan6
sleep 12
kill $LOGPID 2>/dev/null
grep -iE 'odhcp6c|dhcpv6|wan6' /tmp/lm_log6.txt | head -40

echo
echo "===== 3. wan6 拿到的完整信息 ====="
ifstatus wan6 | jsonfilter -e '@.ipv6-address' 2>/dev/null || ifstatus wan6 | grep -A5 ipv6-address
echo "--- ipv6-prefix ---"
ifstatus wan6 | jsonfilter -e '@.ipv6-prefix[*].address' 2>/dev/null
echo "--- dns ---"
ifstatus wan6 | jsonfilter -e '@.dns-server[*]' 2>/dev/null

echo
echo "===== 4. wan 收到的 RA 里的前缀（用 tcpdump 抓 5 秒）====="
which tcpdump >/dev/null 2>&1 && {
  tcpdump -i wan -n -c 6 -t icmp6 and 'ip6[40] == 134' 2>&1 &
  TDPID=$!
  sleep 8
  kill $TDPID 2>/dev/null
} || echo "  无 tcpdump"

echo
echo "===== 5. CPE(203.0.113.1) 的 v6 可达性 ====="
ping6 -c 2 -W 2 -I wan fe80::6043:62ff:feef:910f 2>&1 | tail -3
echo "--- CPE 的 v4 管理页 ---"
wget -q -O - --timeout=5 "http://203.0.113.1/" 2>/dev/null | head -c 300 || echo "  wget 失败"

echo
echo "===== 6. 上游设备侧 v6 的真实出口测试（用 PD 段地址 + 指定 wan）====="
echo "--- 从 wan 发出，源用 PD 段 ---"
ping6 -c 2 -W 2 -I wan -S 2001:db8:9abc:def0 2001:4860:4860::8888 2>&1 | tail -3
echo "--- traceroute6 走 wan ---"
traceroute6 -i wan -s 2001:db8:9abc:def0 -m 4 -w 2 2001:4860:4860::8888 2>&1 | head -6

echo
echo "===== 7. 对比：CPE 自己的 PD 段与出口A PD 段 ====="
echo "wan (CPE) 拿到的 PD : 2001:db8:9abc:def0/56"
echo "pppoe-wan (出口A) 的地址  : 2001:db8:1234:5678.../64"
echo "两者前缀不同 → 不同网络"
echo
echo "===== 8. mwan3 对 wan6 的健康检查日志 ====="
logread 2>/dev/null | grep -i 'mwan3track' | grep -i wan6 | tail -6
