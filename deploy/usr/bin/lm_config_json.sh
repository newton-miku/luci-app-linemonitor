#!/bin/sh
# lm_config_json.sh — 只把 targets.conf 里「看板需要知道」的部分导出成 /www/lm/config.json
# 采集脚本每轮都会调一次（配置改完最多一个采集周期生效）；
# 配置页 /cgi-bin/lm-config 保存后也会立刻调一次（保存即生效）。
#
# 单一数据源是 /etc/line-monitor/targets.conf，这个文件只是它的一个投影。
# 看板读不到它时会退回内置默认值，所以这个脚本挂了不影响监测本身。

. /etc/line-monitor/targets.conf

OUT=/www/lm/config.json

json_esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---- 出口：接口名 -> 显示名 + 类型 ----
# 看板按出口分标签页，type 决定那一页里画 v4 曲线还是 v6 曲线还是两组都画。
elist=""
for e in $EXITS; do
    ifn=$(echo "$e" | cut -d'|' -f1)
    [ -z "$ifn" ] && continue
    lbl=$(echo "$e" | cut -d'|' -f2)
    typ=$(echo "$e" | cut -d'|' -f5)
    case "$typ" in
        v4|v6) ;;
        *) typ="both" ;;
    esac
    [ -n "$elist" ] && elist="$elist,"
    elist="$elist{\"if\":\"$(json_esc "$ifn")\",\"label\":\"$(json_esc "$lbl")\",\"type\":\"$typ\"}"
done

# ---- 目标名列表（看板靠它决定画哪几条曲线）----
jlist() {
    # $1 = 目标串（"名字:地址 名字:地址"）
    out=""
    for t in $1; do
        n=${t%%:*}
        [ -z "$n" ] && continue
        [ -n "$out" ] && out="$out,"
        out="$out\"$(json_esc "$n")\""
    done
    printf '%s' "$out"
}

V4_JSON=$(jlist "$ICMP_TARGETS $HTTP_TARGETS")
V6_JSON=$(jlist "$ICMP6_TARGETS")

# ---- 内网网段（看板只在 TCP 页拿它做提示文字，改动不影响过滤逻辑）----
# 和 tcp_stream.sh 同一套自动识别顺序，保证两边看到的是同一个网段。
resolve_lan_nets() {
    if [ -n "${LAN_NETS:-}" ]; then
        printf '%s' "$LAN_NETS"
        return
    fi
    _a=$(uci -q get network.lan.ipaddr 2>/dev/null)
    _m=$(uci -q get network.lan.netmask 2>/dev/null)
    if [ -n "$_a" ]; then
        [ -z "$_m" ] && _m=255.255.255.0
        printf '%s/%s' "$_a" "$_m"
        return
    fi
    _d=$(uci -q get network.lan.device 2>/dev/null)
    [ -z "$_d" ] && _d=$(uci -q get network.lan.ifname 2>/dev/null)
    [ -z "$_d" ] && _d=br-lan
    ip -4 -o addr show "$_d" 2>/dev/null | awk '{print $4; exit}'
}
LAN_NETS_RESOLVED=$(resolve_lan_nets)

printf '{"title":"%s","subtitle":"%s","lan_nets":"%s","exits":[%s],"targets_v4":[%s],"targets_v6":[%s],"th_max_warn":%s,"th_max_bad":%s,"th_sd_warn":%s,"th_sd_bad":%s}\n' \
    "$(json_esc "$DASH_TITLE")" "$(json_esc "$DASH_SUBTITLE")" \
    "$(json_esc "$LAN_NETS_RESOLVED")" "$elist" "$V4_JSON" "$V6_JSON" \
    "${STAT_MAX_WARN:-300}" "${STAT_MAX_BAD:-1000}" \
    "${STAT_SD_WARN:-50}" "${STAT_SD_BAD:-200}" > "$OUT.tmp" &&
    mv "$OUT.tmp" "$OUT"
