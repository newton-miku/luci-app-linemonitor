#!/bin/sh
# 追查：移动线路出网断点在哪、pppoe-wan2 的物理底层是什么、mwan3 error 16 含义
echo "=== 1) network uci 里的 wan / wan2 / wan6 / wan2_6 ==="
uci show network | grep -E '^network\.(wan|wan2|wan6|wan2_6|wan_6)(\.|$)' | head -n 60

echo
echo "=== 2) 物理链路 ==="
echo "--- ip link (只列 UP 的) ---"
ip -br link show 2>/dev/null || ip link show | grep -E '^[0-9]+:'
echo "--- pppoe-wan2 的底层 ---"
ip -d link show pppoe-wan2 2>/dev/null | head -n 8
echo "--- eth1 速率/双工 ---"
ethtool eth1 2>/dev/null | grep -E 'Speed|Duplex|Link detected' || echo "(no ethtool)"

echo
echo "=== 3) eth1 上有没有 PPPoE 会话 ==="
ps w | grep -E '[p]ppd|[p]ppoe' | head -n 10
echo "--- ppp 接口 ---"
ip -br addr show | grep -E 'ppp|eth1'

echo
echo "=== 4) 上游 192.168.8.1 是什么设备 ==="
echo "--- HTTP 探测 ---"
(echo -e 'GET / HTTP/1.0\r\nHost: 192.168.8.1\r\n\r\n'; sleep 3) | nc 192.168.8.1 80 2>/dev/null | head -n 20 || echo "(80 无响应)"
echo "--- 开放端口快扫 ---"
for p in 22 23 80 443 8080 7547; do
    (echo > /dev/tcp/192.168.8.1/$p) 2>/dev/null && echo "  192.168.8.1:$p open" || true
done

echo
echo "=== 5) eth1 的 DHCP 租约 =="
cat /tmp/dhcp.leases 2>/dev/null | head -n 10
echo "--- udhcpc 相关 ---"
ps w | grep -E '[u]dhcpc|[d]hcp' | head -n 10
ls -la /var/run/udhcpc* /tmp/udhcpc* 2>/dev/null

echo
echo "=== 6) mwan3 的 error 16 是什么 ==="
grep -rn 'ERROR_' /usr/sbin/mwan3track 2>/dev/null | head -n 20
grep -rn 'error' /usr/sbin/mwan3track 2>/dev/null | head -n 20
echo "--- mwan3track 里的 16 ---"
grep -rn '\b16\b' /usr/sbin/mwan3track 2>/dev/null | head -n 10
echo "--- iface_state 文件 ---"
ls -la /var/run/mwan3/iface_state/ 2>/dev/null
for f in /var/run/mwan3/iface_state/*; do
    [ -f "$f" ] && echo "  $f = $(cat $f)"
done
echo "--- mwan3track 状态目录 ---"
for d in /var/run/mwan3track/*/; do
    echo "  [$d]"
    ls -la "$d" 2>/dev/null | tail -n +2 | head -n 8
done

echo
echo "=== 7) 从 eth1 出去的实际路径（网关 192.168.8.1 后面的下一跳） ==="
echo "--- arp ---"
ip neigh show dev eth1 2>/dev/null | head -n 10
echo "--- 到 192.168.8.1 的 traceroute ---"
which traceroute >/dev/null 2>&1 && traceroute -n -m 4 -w 2 192.168.8.1 2>&1 | head -n 8

echo
echo "=== 8) 移动线路上游是否 NAT（用 192.168.8.1 做网关看能否出网） ==="
echo "--- 通过 192.168.8.1 但用默认源地址 ping 223.5.5.5 ---"
ping -c 2 -W 2 -I eth1 223.5.5.5 2>&1 | tail -n 3

echo
echo "=== 9) 反向：电信在线时 eth1 是否被 mwan3 屏蔽（检查 iptables mwan3 链） ==="
iptables -t mangle -L -n 2>/dev/null | grep -E 'eth1|mwan3' | head -n 20
echo "--- mwan3 hooks ---"
iptables -t mangle -S 2>/dev/null | grep -i mwan3 | head -n 20
