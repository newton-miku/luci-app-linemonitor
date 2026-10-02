#!/bin/sh
# 哪种 ping6 写法能在 PPPoE 出口上工作
TGT=2400:3200::1        # 阿里 v6（确定可达）
E1=$(ip -6 addr show dev eth1 scope global | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}')
P6=$(ip -6 addr show dev pppoe-wan2 scope global | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}')
LL=$(ip -6 addr show dev pppoe-wan2 scope link | awk '/inet6 /{sub(/\/.*/,"",$2); print $2; exit}')
echo "eth1 全局   = $E1"
echo "pppoe 全局  = $P6"
echo "pppoe 链路  = $LL"
echo

run() {
    desc="$1"; shift
    out=$("$@" 2>&1 | tail -2 | tr '\n' ' ')
    printf '%-46s -> %s\n' "$desc" "$out"
}

run "ping6 -I eth1"                          ping6 -I eth1 -c 2 -W 2 "$TGT"
run "ping6 -I <eth1全局地址>"                 ping6 -I "$E1" -c 2 -W 2 "$TGT"
run "ping6 -I pppoe-wan2"                    ping6 -I pppoe-wan2 -c 2 -W 2 "$TGT"
run "ping6 -I <pppoe全局地址>"                ping6 -I "$P6" -c 2 -W 2 "$TGT"
run "ping6 -I <pppoe链路本地>"                ping6 -I "$LL" -c 2 -W 2 "$TGT"
run "ping6 -I <pppoe链路本地>%pppoe-wan2"     ping6 -I "$LL%pppoe-wan2" -c 2 -W 2 "$TGT"
run "ping6 -I eth1%<eth1全局>"                ping6 -I "eth1%$E1" -c 2 -W 2 "$TGT"
echo

echo "=== 电信侧：目标换成电信 v6 可达的地址再试 ==="
for T in 2400:3200::1 240e:4c:4008::1 2402:4e00::; do
    run "ping6 -I <pppoe全局> $T" ping6 -I "$P6" -c 2 -W 2 "$T"
    run "ping6 -I pppoe-wan2  $T" ping6 -I pppoe-wan2 -c 2 -W 2 "$T"
done
echo

echo "=== 用源地址选路的证据：ip -6 route get ==="
for T in 2400:3200::1 2402:4e00::; do
    echo "-- 目标 $T"
    echo -n "   from eth1 全局:  "; ip -6 route get "$T" from "$E1" 2>&1 | head -1
    echo -n "   from pppoe 全局: "; ip -6 route get "$T" from "$P6" 2>&1 | head -1
done
echo

echo "=== ping6 支持的选项 ==="
ping6 --help 2>&1 | head -20
