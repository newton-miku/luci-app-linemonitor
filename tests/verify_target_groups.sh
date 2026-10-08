#!/bin/sh
# 在路由器上验「目标分组」：跑**真的** line_monitor.sh（只把 ping/curl/nslookup
# 换成记录桩、把日志与 IP map 路径改到 /tmp），看每个出口实际探测了哪些目标。
# 桩把「探测了哪个地址」记进 /tmp/probe_calls.log，于是「出口声明 公网 就只测公网目标、
# 内网目标被跳过」这件事可以被断言，而不是靠肉眼看代码。

cp /etc/line-monitor/targets.conf /tmp/targets.conf.real

cat > /etc/line-monitor/targets.conf <<'EOF'
DASH_TITLE="分组测试"
DASH_SUBTITLE=""
EXITS="
wan|出口B|auto|256|both|公网
pppoe-wan|出口A||512,768|both|公网
eth9|组网|auto|0|both|内网
"
LAN_NETS=""
ICMP_TARGETS="公网/阿里DNS:223.5.5.5 内网/对端路由:192.168.1.1 内网/对端网关:192.168.1.254"
HTTP_TARGETS="公网/微信:weixin.qq.com 内网/对端面板:192.168.1.1"
ICMP6_TARGETS="公网/阿里v6:2400:3200::1 内网/对端v6:fd00::1"
PING_COUNT=1
CURL_TIMEOUT=1
KEEP_LINES=100
PUBLIC_DNS=223.5.5.5
INTERVAL_MONITOR=60
ALERT_ENABLE=0
EOF

rm -f /tmp/probe_calls.log /tmp/lm_test_history.log
sed -e 's|^LOG=/www/lm/history.log|LOG=/tmp/lm_test_history.log|' \
    -e 's|^IPMAP=/tmp/lm_ipmap.txt|IPMAP=/tmp/lm_test_ipmap.txt|' \
    /usr/bin/line_monitor.sh > /tmp/lm_test.sh

# 桩：记下被探测的地址，返回「成功」格式的假输出。
# nslookup 只对域名给地址，IP 字面量故意不给（跟真机一致：对 IP 调 nslookup 出不来
# Address 行，脚本会回落到直接用原值）。
cat > /tmp/lm_stub.sh <<'STUB'
ping()  { last=""; for a in "$@"; do last="$a"; done; echo "ping4 $last" >> /tmp/probe_calls.log
          echo "1 packets transmitted, 1 packets received, 0% packet loss"
          echo "round-trip min/avg/max = 10.0/10.1/10.2 ms"; }
ping6() { last=""; for a in "$@"; do last="$a"; done; echo "ping6 $last" >> /tmp/probe_calls.log
          echo "1 packets transmitted, 1 packets received, 0% packet loss"
          echo "round-trip min/avg/max = 20.0/20.1/20.2 ms"; }
curl()  { last=""; for a in "$@"; do last="$a"; done; echo "curl  $last" >> /tmp/probe_calls.log
          printf '0.012345'; return 0; }
nslookup() { h=""; for a in "$@"; do case "$a" in 223.5.5.5) ;; *) h="$a";; esac; done
            # 域名含字母，IP 字面量（v4/v6）不含 —— 只给域名地址，
            # 跟真机一致：对 IP 调 nslookup 出不来 Address 行，脚本会回落到用原值。
            case "$h" in
                *[a-zA-Z]*) echo "Name: $h"; echo "Address 1: 203.0.113.9" ;;
                *) exit 1 ;;
            esac; }
STUB
sed -i '1a . /tmp/lm_stub.sh' /tmp/lm_test.sh

echo "=== 1) 真脚本语法体检 ==="
sh -n /usr/bin/line_monitor.sh && echo "OK line_monitor.sh"
sh -n /usr/bin/lm_config_json.sh && echo "OK lm_config_json.sh"
sh -n /tmp/lm_test.sh && echo "OK lm_test.sh"

echo
echo "=== 2) 跑真采集脚本（发包换桩）==="
sh /tmp/lm_test.sh
echo "rc=$?"

echo
echo "=== 3) 实际探测调用（去重计数）==="
sort /tmp/probe_calls.log | uniq -c

echo
echo "=== 4) 断言 ==="
pass=0; fail=0
cnt() { c=$(grep -c "$1" /tmp/probe_calls.log 2>/dev/null); echo "${c:-0}"; }
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; pass=$((pass+1))
        else echo "  FAIL $1  期望[$3] 实际[$2]"; fail=$((fail+1)); fi; }
# 期望：wan 与 pppoe-wan 都声明「公网」，eth9 声明「内网」
chk "公网出口测 223.5.5.5（两家各一次）"      "$(cnt '^ping4 223.5.5.5$')" "2"
chk "内网出口测 192.168.1.1（仅 eth9）"      "$(cnt '^ping4 192.168.1.1$')" "1"
chk "内网出口测 192.168.1.254（仅 eth9）"    "$(cnt '^ping4 192.168.1.254$')" "1"
chk "内网出口测 v6 fd00::1（仅 eth9）"        "$(cnt '^ping6 fd00::1$')" "0"
# eth9 是虚构接口，取不到 v6 源地址 -> 脚本按设计整组记 FAIL 而不发包。
# 「内网 v6 目标只有 eth9 在管」这件事改由 history.log 的键来断言。
chk "对端v6 只挂在 eth9 下"                    "$(grep -c 'v6-eth9|对端v6' /tmp/lm_test_history.log)" "1"
chk "公网出口测 2400:3200::1（两家各一次）"   "$(cnt '^ping6 2400:3200::1$')" "2"
chk "公网域名 curl 两家各一次"                 "$(cnt '^curl  http://203.0.113.9$')" "2"
chk "内网 192.168.1.1 的 curl 仅 eth9"       "$(cnt '^curl  http://192.168.1.1$')" "1"

echo
echo "=== 5) history.log 里的曲线键（应不带分组前缀）==="
tr ' ' '\n' < /tmp/lm_test_history.log | grep '|' | sort -u

echo
echo "=== 6) 还原真实配置 ==="
cp /tmp/targets.conf.real /etc/line-monitor/targets.conf
sh /usr/bin/lm_config_json.sh
echo "已还原："; cat /www/lm/config.json
echo
echo "###### 结果: 通过 $pass 项，失败 $fail 项 ######"
