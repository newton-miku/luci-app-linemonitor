#!/bin/sh
echo "=== 1) dhcp 配置里与 dnsmasq/AAAA 相关的项 ==="
uci show dhcp | grep -iE 'aaaa|filter|dnsmasq|rebind|domain'

echo
echo "=== 2) dnsmasq 完整配置 ==="
uci show dhcp.@dnsmasq[0]

echo
echo "=== 3) dnsmasq 进程参数 ==="
ps w | grep dnsmasq | grep -v grep

echo
echo "=== 4) /etc/dnsmasq.conf 相关项 ==="
grep -vE '^\s*#|^\s*$' /etc/dnsmasq.conf 2>/dev/null | head -n 30

echo
echo "=== 5) dnsmasq 生成的实际配置里有没有 filter-aaaa ==="
grep -rn 'aaaa' /var/etc/dnsmasq.conf.* 2>/dev/null | head -n 10
grep -rn 'aaaa' /tmp/dnsmasq.d/ 2>/dev/null | head -n 10
ls -l /var/etc/dnsmasq.conf.* 2>/dev/null

echo
echo "=== 6) 从路由器本机查 AAAA（问自己） ==="
nslookup -type=AAAA www.taobao.com 127.0.0.1 2>&1 | tail -n 10

echo
echo "=== 7) 直接问电信 DNS（v6） ==="
nslookup -type=AAAA www.taobao.com 2400:3200::1 2>&1 | tail -n 10

echo
echo "=== 8) 问公共 v4 DNS ==="
nslookup -type=AAAA www.taobao.com 223.5.5.5 2>&1 | tail -n 10

echo
echo "=== 9) /etc/config/network 里 lan 的 dns 设置 ==="
uci show network.lan | grep -i dns

echo
echo "=== 10) /etc/resolv.conf ==="
cat /etc/resolv.conf
