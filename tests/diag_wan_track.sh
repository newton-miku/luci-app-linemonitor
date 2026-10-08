#!/bin/sh
# 深挖 wan / wan6 的 mwan3 tracking 失败原因，以及 v6 前缀串线
echo "=== 1) mwan3 uci 接口配置 ==="
uci show mwan3 | grep -E '^mwan3\.(wan|wan6|wan2|wan2_6)(\.|$)' | head -n 60

echo
echo "=== 2) mwan3 全局与策略 ==="
uci show mwan3 | grep -E 'globals|policy|rule' | head -n 40

echo
echo "=== 3) from wan 手动连通性（IPv4） ==="
echo "--- ping 上游网关 203.0.113.1 ---"
ping -c 3 -W 2 -I 203.0.113.114 203.0.113.1 2>&1 | tail -n 4
echo "--- ping 223.5.5.5 ---"
ping -c 3 -W 2 -I 203.0.113.114 223.5.5.5 2>&1 | tail -n 4
echo "--- ping 114.114.114.114 ---"
ping -c 3 -W 2 -I 203.0.113.114 114.114.114.114 2>&1 | tail -n 4
echo "--- ping 8.8.8.8 ---"
ping -c 3 -W 2 -I 203.0.113.114 8.8.8.8 2>&1 | tail -n 4

echo
echo "=== 4) 不带 -I 的对照（走默认路由 = 出口A） ==="
ping -c 2 -W 2 223.5.5.5 2>&1 | tail -n 3

echo
echo "=== 5) wan 的 IPv6 ==="
echo "--- ping6 2400:3200::1 via wan src ---"
ping6 -c 3 -W 2 -I 2001:db8:1234:5678:44ee:91ff:fe20:22b2 2400:3200::1 2>&1 | tail -n 4
echo "--- 2409 的网关 ---"
ip -6 route show dev wan 2>/dev/null | head -n 10
echo "--- ndp 邻居 ---"
ip -6 neigh show dev wan 2>/dev/null | head -n 10

echo
echo "=== 6) wan6 的 error 详情 ==="
ubus call network.interface.wan6 status 2>/dev/null | python3 -m json.tool | head -n 60

echo
echo "=== 7) wan 的完整状态 ==="
ubus call network.interface.wan status 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('up=%s pending=%s available=%s' % (d.get('up'), d.get('pending'), d.get('available')))
print('proto=%s device=%s' % (d.get('proto'), d.get('l3_device')))
print('metric=%s' % d.get('metric'))
print('errors=%s' % d.get('errors'))
for k in ('ipv4-address','route'):
    v=d.get(k)
    if v: print('%s=%s' % (k, v))
"

echo
echo "=== 8) mwan3track 进程 ==="
ps w | grep '[m]wan3track'

echo
echo "=== 9) mwan3 日志里与 wan / wan6 相关的 ==="
logread | grep -i mwan | grep -E 'interface wan |interface wan6|wan \(|wan6 \(' | tail -n 40

echo
echo "=== 10) mwan3 内部状态文件 ==="
ls -la /var/run/mwan3* 2>/dev/null
cat /var/run/mwan3.status 2>/dev/null | head -n 40
cat /var/state/mwan3/* 2>/dev/null | head -n 40
