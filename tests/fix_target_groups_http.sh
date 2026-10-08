#!/bin/sh
# 补刀：HTTP_TARGETS / ICMP6_TARGETS 也要归到「公网」组，
# 否则出口声明了 grp=公网 之后这些目标落到「默认」组，会被全部漏测。
C=/etc/line-monitor/targets.conf

NEWH='HTTP_TARGETS="公网/微信:weixin.qq.com 公网/淘宝:taobao.com 公网/B站:api.bilibili.com 公网/抖音:douyin.com 公网/QQ:qq.com"'
NEW6='ICMP6_TARGETS="公网/阿里v6:2400:3200::1 公网/运营商v6:2409:8080:1::1 公网/国际v6:2620:0:ccc::2"'

awk -v h="$NEWH" -v s="$NEW6" '
  /^HTTP_TARGETS=/   { print h; next }
  /^ICMP6_TARGETS=/  { print s; next }
  { print }
' "$C" > /tmp/tc.new && mv /tmp/tc.new "$C"

echo "=== 三个目标行 ==="
grep -E '^(ICMP_TARGETS|HTTP_TARGETS|ICMP6_TARGETS)=' "$C"

echo
echo "=== 真跑一轮，核对每个出口测了什么 ==="
sh /usr/bin/line_monitor.sh
tail -n 1 /www/lm/history.log | tr ' ' '\n' | grep '|' | sort -u

echo
echo "=== 断言：公网出口该有 HTTP 目标、内网出口不该有 ==="
L=$(tail -n 1 /www/lm/history.log)
n_http_wan=$(printf '%s' "$L" | tr ' ' '\n' | grep -c '^wan|微信')
n_http_ts=$(printf '%s' "$L" | tr ' ' '\n' | grep -c '^tun0|微信')
n_pub_ts=$(printf '%s' "$L" | tr ' ' '\n' | grep -c '^tun0|阿里DNS')
n_int_wan=$(printf '%s' "$L" | tr ' ' '\n' | grep -c '^wan|对端一')
echo "wan 测微信(=1): $n_http_wan"
echo "tun0 测微信(=0): $n_http_ts"
echo "tun0 测公网DNS(=0): $n_pub_ts"
echo "wan 测内网对端(=0): $n_int_wan"
[ "$n_http_wan" = "1" ] && [ "$n_http_ts" = "0" ] && [ "$n_pub_ts" = "0" ] && [ "$n_int_wan" = "0" ] \
  && echo "全部通过" || echo "有不符合预期的项"

echo
echo "=== config.json ==="
sh /usr/bin/lm_config_json.sh
cat /www/lm/config.json
