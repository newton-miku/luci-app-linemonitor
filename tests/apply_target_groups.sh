#!/bin/sh
# 给路由器上**正在用**的 targets.conf 打上「目标分组 + tailscale 内网目标」。
# install.sh 有意不覆盖已有配置，所以这一步单独做，且必须先备份。
C=/etc/line-monitor/targets.conf
cp "$C" /tmp/targets.conf.bak.$(date +%s)
echo "已备份到 /tmp/targets.conf.bak.*"

# --- 1) EXITS 块整体替换（保留三段注释里的格式说明，只换数据行）---
awk '
  /^EXITS="/ { inex=1; print; print "eth1|移动|auto|256|both|公网"; print "pppoe-wan2|电信||512,768|both|公网"; print "tailscale0|tailscale组网|||v4|内网"; next }
  inex && /^"/ { inex=0 }
  inex { next }
  { print }
' "$C" > /tmp/tc.new && mv /tmp/tc.new "$C"

# --- 2) ICMP_TARGETS 行替换（加内网组）---
NEW='ICMP_TARGETS="公网/阿里DNS:223.5.5.5 公网/腾讯DNS:119.29.29.29 公网/CNNIC:1.2.4.8 内网/op-nj:100.82.79.44 内网/cd-ubuntu22:100.92.175.22 内网/ubunt-hb:100.109.107.128"'
awk -v new="$NEW" '/^ICMP_TARGETS=/ { print new; next } { print }' "$C" > /tmp/tc.new && mv /tmp/tc.new "$C"

echo
echo "=== 结果 ==="
grep -A6 '^EXITS=' "$C"
grep '^ICMP_TARGETS=' "$C"
echo
echo "=== 生效检查（真跑一轮采集，看是否只测该测的）==="
. "$C"
echo "出口: $EXITS"
echo
sh /usr/bin/line_monitor.sh
echo "采集 rc=$?"
tail -n 1 /www/lm/history.log | tr ' ' '\n' | grep '|' | sort -u
echo
echo "=== config.json ==="
cat /www/lm/config.json
