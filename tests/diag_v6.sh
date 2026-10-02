#!/bin/sh
# v6 出口排查：电信 IPv6 到底挂在哪个接口上，采集为什么全 FAIL
echo "===== 1) 所有接口的 IPv6 地址 ====="
ip -6 addr show | awk '/^[0-9]+: /{ifc=$2} /inet6 /{print ifc, $2, $3, $4, $5, $6}'

echo
echo "===== 2) 各接口 IPv6 链路本地地址（ping6 -I 用的就是它）====="
for i in $(ls /sys/class/net); do
    a=$(ip -6 addr show dev "$i" scope link 2>/dev/null | awk '/inet6 fe80/{print $2; exit}')
    g=$(ip -6 addr show dev "$i" scope global 2>/dev/null | awk '/inet6 /{print $2; exit}')
    printf '%-14s link=%-22s global=%s\n' "$i" "${a:-无}" "${g:-无}"
done

echo
echo "===== 3) uci network 里的接口与 device ====="
uci show network 2>/dev/null | grep -E '\.(proto|device|ifname|ip6addr|ip6ifaceid)=' | sort

echo
echo "===== 4) IPv6 路由表 ====="
ip -6 route show | head -30

echo
echo "===== 5) targets.conf 的出口与 v6 目标 ====="
grep -E '^(EXITS|ICMP6_TARGETS|PUBLIC_DNS)=' /etc/line-monitor/targets.conf

echo
echo "===== 6) 实测 ping6（各接口）====="
for tgt in 2400:3200::1 240e:4c:4008::1; do
    for i in eth1 pppoe-wan2 WAN2_6 wan6; do
        ip link show "$i" >/dev/null 2>&1 || continue
        out=$(ping6 -I "$i" -c 2 -W 2 "$tgt" 2>&1 | tail -2 | tr '\n' ' ')
        printf 'ping6 -I %-12s %-24s -> %s\n' "$i" "$tgt" "$out"
    done
done

echo
echo "===== 7) 实测 ping6 不带 -I（走默认路由）====="
for tgt in 2400:3200::1 240e:4c:4008::1; do
    out=$(ping6 -c 2 -W 2 "$tgt" 2>&1 | tail -2 | tr '\n' ' ')
    printf '%-24s -> %s\n' "$tgt" "$out"
done

echo
echo "===== 8) 最近一条采集日志里的 v6 字段 ====="
tail -1 /www/lm/history.log | tr ' ' '\n' | grep -E '^v6-' | head -20
