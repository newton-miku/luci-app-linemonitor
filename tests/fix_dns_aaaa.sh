#!/bin/sh
echo "=== 1) 5335 端口是什么服务 ==="
netstat -lnp 2>/dev/null | grep 5335
echo "--- 相关进程 ---"
ps w | grep -iE 'mosdns|adguard|smartdns|clash|sing-box|singbox|passwall|v2ray|xray|ssr|openclash' | grep -v grep

echo
echo "=== 2) 关掉 filter_aaaa ==="
uci set dhcp.@dnsmasq[0].filter_aaaa='0'
uci commit dhcp
echo "filter_aaaa = $(uci get dhcp.@dnsmasq[0].filter_aaaa)"

echo
echo "=== 3) 重启 dnsmasq ==="
/etc/init.d/dnsmasq restart
sleep 8
echo "dnsmasq pid: $(pidof dnsmasq)"

echo
echo "=== 4) 确认生成配置里 filter-aaaa 已消失 ==="
if grep -n 'filter-aaaa' /var/etc/dnsmasq.conf.* 2>/dev/null; then
    echo "!!! STILL PRESENT !!!"
else
    echo "OK: no filter-aaaa"
fi
echo "--- 生成配置全文 ---"
cat /var/etc/dnsmasq.conf.cfg01411c 2>/dev/null | head -n 30

echo
echo "=== 5) 从本机 dnsmasq 查 AAAA ==="
nslookup -type=AAAA www.taobao.com 127.0.0.1 2>&1 | tail -n 10
echo "--- 换语法 ---"
nslookup -t AAAA www.taobao.com 127.0.0.1 2>&1 | tail -n 10

echo
echo "=== 6) 直接问 5335（绕过 dnsmasq） ==="
nslookup -type=AAAA www.taobao.com 127.0.0.1 2>&1 | tail -n 6

echo
echo "=== 7) 用文本工具确认 AAAA 是否返回 ==="
which dig drill host kdig 2>/dev/null
echo "(以上是路由器上可用的 DNS 工具)"
