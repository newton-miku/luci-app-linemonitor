#!/bin/sh
echo "=== ip -6 rule show ==="
ip -6 rule show

echo
echo "=== mwan3 表 4 的 v6 路由 ==="
ip -6 route show table 4 2>&1 | head -15

echo
echo "=== 表 all 里 240e:358 的路由 ==="
ip -6 route show table all 2>&1 | grep '240e:358'

echo
echo "=== ip6tables mangle OUTPUT ==="
ip6tables -t mangle -S OUTPUT 2>&1 | head -15

echo
echo "=== 路由器本机 ping6 -I pppoe-wan2（接口名）==="
ping6 -c 2 -W 2 -I pppoe-wan2 2400:3200::1 2>&1 | tail -3

echo
echo "=== 电信 v6 自己的 DNS 240e:f:a::6 ==="
ping6 -c 2 -W 2 -I 240e:358:a001:c3e7:982a:77fb:1077:6572 240e:f:a::6 2>&1 | tail -3

echo
echo "=== 用 TCP 测电信 v6（curl，绕开 ICMP 限制）==="
curl -6 -s -o /dev/null -w 'taobao http=%{http_code} ip=%{remote_ip} t=%{time_total}\n' --max-time 8 https://www.taobao.com 2>&1
curl -6 -s -o /dev/null -w 'qq http=%{http_code} ip=%{remote_ip} t=%{time_total}\n' --max-time 8 https://www.qq.com 2>&1

echo
echo "=== 绑定电信源地址的 curl ==="
curl -6 -s -o /dev/null -w 'taobao http=%{http_code} ip=%{remote_ip} t=%{time_total}\n' --interface 240e:358:a001:c3e7:982a:77fb:1077:6572 --max-time 8 https://www.taobao.com 2>&1
