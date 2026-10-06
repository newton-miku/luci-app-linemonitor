#!/bin/sh
# 全面网络侦察：接口状态 / mwan3 / 策略路由 / 各出口连通性
echo "=== 1) 网络接口状态 ==="
ubus call network.interface dump 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for i in d.get('interface', []):
    name = i.get('interface')
    if name == 'loopback':
        continue
    l3 = i.get('l3_device', {})
    if isinstance(l3, dict):
        l3 = l3.get('device', '-')
    proto = i.get('proto', '-')
    v4 = [a.get('address') for a in i.get('ipv4-address', [])]
    v6 = [a.get('address') for a in i.get('ipv6-address', [])]
    v6p = [a.get('address') for a in i.get('ipv6-prefix', [])]
    print('%-14s up=%-5s proto=%-9s dev=%-12s v4=%-16s v6=%-28s v6pfx=%s' % (
        name, i.get('up'), proto, l3,
        ','.join(v4) or '-', ','.join(v6) or '-', ','.join(v6p) or '-'))
"

echo
echo "=== 2) mwan3 status ==="
mwan3 status 2>/dev/null | head -n 60 || echo "(mwan3 status 不可用)"

echo
echo "=== 3) 策略路由规则 ==="
echo "--- IPv4 rules ---"
ip rule show
echo "--- IPv6 rules ---"
ip -6 rule show

echo
echo "=== 4) 各表默认路由 ==="
echo "--- IPv4 default routes (table all) ---"
ip route show table all | grep -E 'default' | head -n 20
echo "--- IPv6 default routes (table all) ---"
ip -6 route show table all | grep -E 'default' | head -n 20

echo
echo "=== 5) 每张表的内容（只看 default） ==="
for t in $(ip route show table all | awk '/^default/{print $NF, $(NF-1)}' | sort -u | head -n 20); do :; done
for tbl in 1 2 3 4 5 6 7 8 100 101 102 103 104 105 106 107 108; do
    r=$(ip route show table $tbl 2>/dev/null | grep '^default')
    [ -n "$r" ] && echo "v4 table $tbl: $r"
done
for tbl in 1 2 3 4 5 6 7 8 100 101 102 103 104 105 106 107 108; do
    r=$(ip -6 route show table $tbl 2>/dev/null | grep '^default')
    [ -n "$r" ] && echo "v6 table $tbl: $r"
done

echo
echo "=== 6) 接口 verbose (ifstatus) ==="
for iface in wan wan6 wan2 wan6_2 wan_2; do
    echo "--- $iface ---"
    ifstatus "$iface" 2>/dev/null | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('  (无此接口)'); raise SystemExit
print('  up=%s pending=%s proto=%s' % (d.get('up'), d.get('pending'), d.get('proto')))
print('  l3_device=%s' % (d.get('l3_device')))
for k in ('ipv4-address','ipv6-address','ipv6-prefix','dns-server'):
    v = d.get(k)
    if v: print('  %s=%s' % (k, v))
err = d.get('errors')
if err: print('  errors=%s' % err)
"
done

echo
echo "=== 7) mwan3 日志 ==="
logread 2>/dev/null | grep -i -E 'mwan' | tail -n 30

echo
echo "=== 8) 网络相关日志尾部 ==="
logread 2>/dev/null | grep -i -E 'pppoe|pppd|odhcp|netifd|wan' | tail -n 25
