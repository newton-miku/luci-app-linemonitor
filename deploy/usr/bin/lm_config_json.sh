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

# ---- 出口：接口名 -> 显示名 + 类型 + 该出口监测的目标名清单 ----
# 看板按出口分标签页，type 决定那一页里画 v4 曲线还是 v6 曲线还是两组都画。
# targets 是这个出口第 6 字段里声明的目标名清单，逗号分隔；空串 = 该出口测全部目标。
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
    tgts=$(echo "$e" | cut -d'|' -f6)
    [ "$tgts" = "*" ] && tgts=""
    [ -n "$elist" ] && elist="$elist,"
    elist="$elist{\"if\":\"$(json_esc "$ifn")\",\"label\":\"$(json_esc "$lbl")\",\"type\":\"$typ\",\"targets\":\"$(json_esc "$tgts")\"}"
done

# ---- 哪些出口在监测这个目标 ----
# 这是「出口侧的清单」的另一种读法，不额外存任何东西，所以两边永远一致。
# 出口第 6 字段留空 = 全测，所以每个出口都要判一次；输出 JSON 字符串数组，顺序跟 EXITS 一致。
# $1 = 目标名（已剥掉「分组/」前缀）
exits_for() {
    _out=""
    for _e in $EXITS; do
        _if=$(echo "$_e" | cut -d'|' -f1)
        [ -z "$_if" ] && continue
        _tg=$(echo "$_e" | cut -d'|' -f6)
        if [ -z "$_tg" ] || [ "$_tg" = "*" ]; then
            _hit=1
        else
            case ",$_tg," in
                *",$1,"*) _hit=1 ;;
                *)        _hit=0 ;;
            esac
        fi
        [ "$_hit" = "1" ] || continue
        [ -n "$_out" ] && _out="$_out,"
        _out="$_out\"$(json_esc "$_if")\""
    done
    printf '[%s]' "$_out"
}

# ---- 目标列表：名字（去分组前缀）+ 分组 + 所属类别 + 哪些出口在测 ----
# 名字里不写分组前缀，看板上就是「对端路由」而不是「内网/对端路由」；
# 分组单独放在 grp 字段，只在统计表里当分类标签显示。
# kind 是 icmp / http / v6，看板据此决定统计表归到哪一栏。
jlist() {
    # $1 = 目标串（"分组/名字:地址 名字:地址"）$2 = kind
    out=""
    for t in $1; do
        raw=${t%%:*}
        [ -n "$raw" ] || continue
        gp="默认"
        case "$raw" in
            */*) gp=${raw%%/*}; raw=${raw#*/} ;;
        esac
        [ -n "$raw" ] || continue
        [ -n "$out" ] && out="$out,"
        out="$out{\"name\":\"$(json_esc "$raw")\",\"grp\":\"$(json_esc "$gp")\",\"kind\":\"$2\",\"exits\":$(exits_for "$raw")}"
    done
    printf '%s' "$out"
}

V4_JSON=$(jlist "$ICMP_TARGETS" icmp)
V4_JSON="$V4_JSON,$(jlist "$HTTP_TARGETS" http)"
V4_JSON="${V4_JSON#,}"
V6_JSON=$(jlist "$ICMP6_TARGETS" v6)

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
