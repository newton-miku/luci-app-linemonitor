#!/bin/sh
# 验证升级结果
echo "=== targets.conf 的关键项 ==="
grep -E '^(DASH_TITLE|DASH_SUBTITLE|LAN_PREFIX|PING_COUNT|CURL_TIMEOUT|KEEP_LINES|PUBLIC_DNS|INTERVAL_)' /etc/line-monitor/targets.conf
echo "--- EXITS ---"
awk '/^EXITS="/{f=1;next} f&&/^"/{f=0} f{print}' /etc/line-monitor/targets.conf

echo ""
echo "=== /www/lm/config.json ==="
cat /www/lm/config.json

echo ""
echo "=== CGI GET（前 12 行）==="
# 直接调脚本模拟 uhttpd 的调用
REQUEST_METHOD=GET sh /www/cgi-bin/lm-config 2>&1 | head -12

echo ""
echo "=== 手动跑一次 tcp_stream.sh 看出口标识 ==="
sh /usr/bin/tcp_stream.sh
echo "tcp.json 大小: $(wc -c < /www/lm/tcp.json)"
echo "--- 出口分布 ---"
jsonfilter -i /www/lm/tcp.json -e '@.streams[*].iface' 2>/dev/null | sort | uniq -c
echo "--- mark 分布 ---"
awk '$3=="tcp" {for(i=11;i<=NF;i++) if(substr($i,1,5)=="mark=") {c[substr($i,6)]++; break}} END {for(m in c) print m, c[m]}' /proc/net/nf_conntrack | sort -n
