#!/bin/sh
echo "=== 加规则：源在 240e::/16 的本机 v6 流量走 main ==="
ip -6 rule add from 240e::/16 lookup main priority 100 2>&1
ip -6 rule show | head -4

echo
echo "=== 验证 1：出口A v6 本机连通 ==="
ping6 -c 3 -W 2 -I 2001:db8:1234:5678 2400:3200::1 2>&1 | tail -3
ping6 -c 3 -W 2 -I 2001:db8:1234:5678 240e:f:a::6 2>&1 | tail -3

echo
echo "=== 验证 2：出口B v6 不受影响 ==="
ping6 -c 3 -W 2 -I 2001:db8:4321:9abc 2409:8080:1::1 2>&1 | tail -3

echo
echo "=== 验证 3：组网客户端 ==="
ip -6 route show table main | grep -i 组网客户端 | head -3
组网客户端 status 2>&1 | head -5

echo
echo "=== 验证 4：DNS 正常 ==="
nslookup www.baidu.com 127.0.0.1 2>&1 | tail -6

echo
echo "=== 验证 5：curl v4 不受影响 ==="
curl -4 -s -o /dev/null -w 'baidu v4 http=%{http_code} ip=%{remote_ip} t=%{time_total}\n' --max-time 8 https://www.baidu.com 2>&1

echo
echo "=== 当前规则表 ==="
ip -6 rule show
