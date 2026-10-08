#!/bin/sh
# 探测 mark -> 出口接口 的真实映射，以及 uhttpd 的 CGI 能力
echo "=== conntrack 里的 mark 值分布 ==="
awk '$3=="tcp" {for(i=11;i<=NF;i++) if(substr($i,1,5)=="mark=") {c[substr($i,6)]++; break}} END {for(m in c) print m, c[m]}' /proc/net/nf_conntrack | sort -n
echo ""
echo "=== 各 mark 实际走哪个接口 (ip route get 1.1.1.1) ==="
for m in 0 256 512 768 1024 1280 1536; do
  out=$(ip route get 1.1.1.1 mark $m 2>/dev/null | head -1)
  echo "mark=$m -> $out"
done
echo ""
echo "=== ip rule ==="
ip rule show
echo ""
echo "=== 路由表 1 / 2 的默认路由 ==="
echo "[table 1]"; ip route show table 1 2>/dev/null | awk '/default|^default/{print}' 
ip route show table 1 2>/dev/null | head -2
echo "[table 2]"; ip route show table 2 2>/dev/null | head -2
echo ""
echo "=== uhttpd 配置 ==="
uci show uhttpd 2>/dev/null
echo ""
echo "=== /www/cgi-bin ==="
ls -l /www/cgi-bin/ 2>/dev/null
echo ""
echo "=== 接口地址 ==="
ip -4 addr show wan 2>/dev/null | awk '/inet /{print "wan:", $2}'
ip -4 addr show pppoe-wan 2>/dev/null | awk '/inet /{print "pppoe-wan:", $2}'
