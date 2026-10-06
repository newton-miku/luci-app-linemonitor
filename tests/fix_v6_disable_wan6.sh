#!/bin/sh
echo "=== 1) 先在 eth1 上挂一个静态地址，强制走电信源测一次 ==="
ping6 -c 3 -W 3 -I 240e:359:a053:9e00::1 240e:f:a::6 2>&1 | tail -n 4
curl -6 -s -o /dev/null -w "curl6(src=240e:359:a053:9e00::1) http=%{http_code} time=%{time_total}\n" --interface 240e:359:a053:9e00::1 --max-time 10 https://ipv6.baidu.com

echo
echo "=== 2) 看看内核给 2400:3200::1 选哪条路 ==="
ip -6 route get 2400:3200::1 2>&1 | head -n 3

echo
echo "=== 3) 禁用 network.wan6（移动 v6 断 123h，且上游在灌错 PD） ==="
uci set network.wan6.disabled='1'
uci commit network
uci show network.wan6 | grep -E 'disabled|reqprefix'

echo
echo "=== 4) 停掉 wan6 并重启 odhcpd ==="
ubus call network.interface.wan6 down 2>/dev/null
/etc/init.d/odhcpd restart
sleep 10

echo
echo "=== 5) 改后：v6 默认路由 ==="
ip -6 route show default

echo
echo "=== 6) br-lan 地址 ==="
ip -6 addr show br-lan | grep inet6

echo
echo "=== 7) eth1 是否还有 v6 地址 ==="
ip -6 addr show eth1 | grep inet6

echo
echo "=== 8) 从路由器测 v6（不指定源） ==="
curl -6 -s -o /dev/null -w "curl6 http=%{http_code} time=%{time_total}\n" --max-time 10 https://ipv6.baidu.com
ping6 -c 3 -W 3 240e:f:a::6 2>&1 | tail -n 3

echo
echo "=== 9) 抓 br-lan 的 RA 关键字段 ==="
timeout 12 tcpdump -i br-lan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | grep -E 'length 1|prefix info|router lifetime|rdnss' | head -n 20

echo
echo "=== 10) odhcpd 日志 ==="
logread | grep -i odhcpd | tail -n 6
