#!/bin/sh
# 排查：tailscale 一连上就打不开路由器 Web 界面。
# 重点看：宣告了哪些路由 / 是否 exit node / tailscale0 是否被防火墙拦 / 有无 MASQUERADE。

echo "===== 1. tailscale status ====="
tailscale status 2>&1 | head -20
echo
echo "===== 2. advertise-routes / exit-node ====="
tailscale debug prefs 2>&1 | grep -E '"(RouteAll|ExitNodeID|ExitNodeIP|AdvertiseRoutes|CorpDNS|WantRunning|NoSNAT)"' 
echo "--- AdvertiseRoutes 明细 ---"
tailscale debug prefs 2>&1 | sed -n '/AdvertiseRoutes/,/]/p' | head -30
echo
echo "===== 3. tailscale 接口 ====="
ip -4 addr show tailscale0 2>&1
ip -6 addr show tailscale0 2>&1 | head -5
ip link show tailscale0 2>&1 | head -2
echo
echo "===== 4. 路由表里的 tailscale ====="
ip route show table all 2>/dev/null | grep -i tailscale
echo "--- 主表 192.168.66 相关 ---"
ip route show 2>/dev/null | grep -E '192\.168\.66|default'
echo
echo "===== 5. ip rule ====="
ip rule show 2>&1
echo
echo "===== 6. 防火墙 NAT / filter 里的 tailscale ====="
iptables -t nat -S 2>/dev/null | grep -iE 'tailscale|ts-|100\.' | head -20
echo "--- filter INPUT ---"
iptables -S INPUT 2>/dev/null | head -20
echo "--- chain ts-input 是否存在 ---"
iptables -S ts-input 2>/dev/null | head -20
echo
echo "===== 7. tailscaled 版本与启动参数 ====="
tailscale version 2>&1 | head -3
ps w | grep '[t]ailscaled' | head -3
echo
echo "===== 8. nftables（有些固件用 nft） ====="
nft list ruleset 2>/dev/null | grep -iE 'tailscale|ts_input|100\.' | head -20
echo
echo "===== 9. 本机能否访问自己 web ====="
wget -q -O /dev/null -T 3 http://192.168.66.1/cgi-bin/luci 2>&1 && echo "本机访问 luci OK" || echo "本机访问 luci 失败"
wget -q -O /dev/null -T 3 http://127.0.0.1/cgi-bin/luci 2>&1 && echo "127.0.0.1 luci OK" || echo "127.0.0.1 luci 失败"
echo
echo "===== 10. uhttpd 监听地址 ====="
netstat -tlnp 2>/dev/null | grep -E '80|443' | head -5
uci show uhttpd 2>/dev/null | grep -E 'listen|port|interface' | head -10
