#!/bin/sh
# 锁定：odhcpd 为什么没给 LAN 下发 IPv6 默认路由
echo "=== 1) dhcp 里 lan 的 ra/dhcpv6 配置 ==="
uci show dhcp.lan 2>/dev/null
echo "--- odhcpd 全局 ---"
uci show dhcp | grep -E 'odhcpd|@odhcpd' | head -n 20

echo
echo "=== 2) odhcpd 的 v6 租约/前缀状态 ==="
ubus call dhcp ipv6leases 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('(无法解析 or 无数据)'); raise SystemExit
devs = d.get('device', {})
for dev, info in devs.items():
    print('device:', dev)
    for k, v in info.items():
        if k == 'leases':
            print('  leases: %d 条' % len(v))
            for L in v[:8]:
                print('    ', {kk: L.get(kk) for kk in ('ipv6','hostname','duid')})
        elif k in ('ra','prefixes','routes'):
            print('  %s = %s' % (k, v))
        else:
            print('  %s = %s' % (k, v))
" 2>/dev/null || ubus call dhcp ipv6leases 2>/dev/null | head -n 40

echo
echo "=== 3) odhcpd 进程参数与日志 ==="
ps w | grep '[o]dhcpd'
logread | grep -i odhcpd | tail -n 25

echo
echo "=== 4) br-lan 上实抓 RA（10 秒） ==="
if which tcpdump >/dev/null 2>&1; then
    timeout 10 tcpdump -i br-lan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | head -n 40
else
    echo "(no tcpdump)"
fi

echo
echo "=== 5) uci network.lan 全文 ==="
uci show network.lan 2>/dev/null

echo
echo "=== 6) 全部 4200000000 规则 ==="
ip -6 rule show | tail -n 25

echo
echo "=== 7) odhcpd 状态文件 ==="
ls -la /var/run/odhcpd* /tmp/odhcpd* 2>/dev/null
cat /var/run/odhcpd.state 2>/dev/null | head -n 20

echo
echo "=== 8) 内核里 br-lan 的 RA 相关参数 ==="
sysctl net.ipv6.conf.br-lan 2>/dev/null | grep -E 'forwarding|accept_ra|autoconf|router' | head -n 20

echo
echo "=== 9) 全部 logread 里的 prefix 冲突线索 ==="
logread | grep -iE 'odhcpd|prefix' | grep -viE 'mwan3|mwan3track' | tail -n 40
