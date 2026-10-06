#!/bin/sh
# 把 LAN 的 IPv6 从 relay 改成 server：路由器自己用 PD 前缀给 LAN 发 RA + DHCPv6
echo "=== 0) 备份当前配置 ==="
BK=/tmp/uci-backup-$(date +%s).txt
uci export > "$BK"
echo "backup -> $BK"
ls -l "$BK"

echo
echo "=== 1) 改前配置快照 ==="
uci show dhcp | grep -E "(lan|wan6|wan2_6)\.(ra|dhcpv6|ndp|master|ndproxy_slave|ra_management|ra_flags)="

echo
echo "=== 2) LAN: relay -> server ==="
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'
uci delete dhcp.lan.ndp 2>/dev/null
uci delete dhcp.lan.ndproxy_slave 2>/dev/null
uci set dhcp.lan.ra_management='1'
uci commit dhcp
echo "done"

echo
echo "=== 3) 只保留 wan2_6 一个 relay master ==="
uci delete dhcp.wan6.master 2>/dev/null
uci commit dhcp
echo "done"

echo
echo "=== 4) 改后配置 ==="
uci show dhcp | grep -E "(lan|wan6|wan2_6)\.(ra|dhcpv6|ndp|master|ndproxy_slave|ra_management|ra_flags)="

echo
echo "=== 5) 重启 odhcpd ==="
/etc/init.d/odhcpd restart
sleep 6
echo "odhcpd pid: $(pidof odhcpd)"

echo
echo "=== 6) 等 25 秒让 RA 发出去 ==="
sleep 25

echo
echo "=== 7) br-lan 的 RA（15 秒，看 length 与 prefix info） ==="
timeout 15 tcpdump -i br-lan -n -vv 'icmp6 and ip6[40] == 134' 2>&1 | head -n 40

echo
echo "=== 8) br-lan 当前 v6 地址 ==="
ip -6 addr show br-lan | grep inet6

echo
echo "=== 9) odhcpd 日志 ==="
logread | grep -i odhcpd | tail -n 15

echo
echo "=== 10) v6 默认路由与策略 ==="
ip -6 route show default
ip -6 rule show | head -n 10
