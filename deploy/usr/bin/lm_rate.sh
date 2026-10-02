#!/bin/sh
# lm_rate.sh — 采样接口实时速率，写 /tmp/lm_rate.json（在 RAM 里，不磨 flash）
#
# 原理：/proc/net/dev 里每个接口有累计 rx/tx 字节数，两次采样求差除以间隔即速率。
# 状态存 /tmp/lm_rate.state，格式：<接口> <rx字节> <tx字节> <采样时刻>
# 第一次跑只记基线（速率为 0），下次才有数。
#
# 采集的接口由 targets.conf 的 RATE_IFACES 决定，缺省是两条出口 + 内网网桥。
# 出口的显示名从 EXITS 里取，取不到就用接口名本身。

CONF=/etc/line-monitor/targets.conf
[ -f "$CONF" ] && . "$CONF"

RATE_IFACES=${RATE_IFACES:-"eth1 pppoe-wan2 br-lan"}
STATE=/tmp/lm_rate.state
# 写 /tmp（RAM）：2 秒一次的话往 overlay 上写就把 flash 磨坏了，
# CGI /cgi-bin/lm-rate 直接读这个文件。
OUT=/tmp/lm_rate.json

now=$(date +%s)

# 把 /proc/net/dev 读成 "<接口> <rx> <tx>" 三列，只留关心的接口
devs=$(awk -v want="$RATE_IFACES" '
    BEGIN {
        n = split(want, w, " ")
        for (i = 1; i <= n; i++) keep[w[i]] = 1
    }
    /:/ {
        line = $0
        sub(/^[ \t]+/, "", line)
        split(line, a, ":")
        iface = a[1]
        gsub(/[ \t]/, "", iface)
        if (!(iface in keep)) next
        split(a[2], f, " ")
        # 第 1 个字段是 rx bytes，第 9 个是 tx bytes
        printf "%s %s %s\n", iface, f[1], f[9]
    }
' /proc/net/dev)

# 显示名映射：EXITS 的字段是 接口|显示名|源IP|mark|类型
label_of() {
    echo "$EXITS" | tr ' ' '\n' | awk -F'|' -v i="$1" '$1 == i { print $2; exit }'
}

# 读旧状态
old_rx() { awk -v i="$1" '$1 == i { print $2; exit }' "$STATE" 2>/dev/null; }
old_tx() { awk -v i="$1" '$1 == i { print $3; exit }' "$STATE" 2>/dev/null; }
old_ts() { awk -v i="$1" '$1 == i { print $4; exit }' "$STATE" 2>/dev/null; }

json=""
state_new=""
sep=""

for iface in $RATE_IFACES; do
    line=$(echo "$devs" | awk -v i="$iface" '$1 == i { print; exit }')
    [ -n "$line" ] || continue
    rx=$(echo "$line" | awk '{print $2}')
    tx=$(echo "$line" | awk '{print $3}')

    prx=$(old_rx "$iface")
    ptx=$(old_tx "$iface")
    pts=$(old_ts "$iface")

    # 速率单位：bytes/s；接口不存在或首次采样时给 0
    rxs=0
    txs=0
    if [ -n "$prx" ] && [ -n "$pts" ]; then
        dt=$((now - pts))
        [ "$dt" -gt 0 ] || dt=1
        # 计数器回绕（重启 / 32 位回绕）时差值会为负，夹到 0
        drx=$((rx - prx))
        dtx=$((tx - ptx))
        [ "$drx" -ge 0 ] || drx=0
        [ "$dtx" -ge 0 ] || dtx=0
        rxs=$((drx / dt))
        txs=$((dtx / dt))
    fi

    lbl=$(label_of "$iface")
    [ -n "$lbl" ] || lbl="$iface"

    json="$json$sep{\"if\":\"$iface\",\"label\":\"$lbl\",\"rx\":$rxs,\"tx\":$txs}"
    sep=","
    state_new="$state_new$iface $rx $tx $now
"
done

printf '{"ts":%s,"rates":[%s]}\n' "$now" "$json" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
printf '%s' "$state_new" > "$STATE.tmp"
mv "$STATE.tmp" "$STATE"
