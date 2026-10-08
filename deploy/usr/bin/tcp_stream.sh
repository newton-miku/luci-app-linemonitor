#!/bin/sh
# tcp_stream.sh — 每 INTERVAL_TCP 秒采集内网设备活跃 TCP 连接，覆盖写入 /www/lm/tcp.json
# 数据源: /proc/net/nf_conntrack
#
# 字段位置: $6=TCP状态 $7=src $8=dst $9=sport $10=dport，mark 在 $11 之后。
# $7/$8 的值形如 "src=192.168.1.100"（自带前缀），必须先剥掉才能比较和查表。
#
# 出口判定: 靠 conntrack 的 fwmark，映射表来自 targets.conf 里 EXITS 的第 4 列。
# 输出的是**接口名**（wan / pppoe-wan），显示名由看板决定，
# 这样改名字不用动采集脚本。
#
# 为什么整段用 awk 而不是 shell 循环: conntrack 常态 150+ 行，
# 在这台路由器上纯 shell 逐行处理要 4~5 秒（分词 + 逐字段扫描的固定开销），
# 而采集周期本身只有 5 秒。awk 单进程一次过，实测 < 0.2 秒。

. /etc/line-monitor/targets.conf

# 内网网段：配置里给了就用配置，留空则自动识别。
# 自动识别的顺序：UCI 的 lan 接口 -> 它的 device 的实际地址 -> br-lan。
# 用 ipaddr+netmask 而不是前缀匹配，是为了支持任意掩码（/8 /16 /22 /25 ...）。
resolve_lan_nets() {
    if [ -n "${LAN_NETS:-}" ]; then
        echo "$LAN_NETS"
        return
    fi
    _a=$(uci -q get network.lan.ipaddr 2>/dev/null)
    _m=$(uci -q get network.lan.netmask 2>/dev/null)
    if [ -n "$_a" ]; then
        [ -z "$_m" ] && _m=255.255.255.0
        echo "$_a/$_m"
        return
    fi
    _d=$(uci -q get network.lan.device 2>/dev/null)
    [ -z "$_d" ] && _d=$(uci -q get network.lan.ifname 2>/dev/null)
    [ -z "$_d" ] && _d=br-lan
    ip -4 -o addr show "$_d" 2>/dev/null | awk '{print $4; exit}'
}
LAN_NETS_RESOLVED=$(resolve_lan_nets)

IPMAP=/tmp/lm_ipmap.txt
OUT=/www/lm/tcp.json
TS=$(date +%s)

# EXITS 的 mark 列 -> "256:wan,512:pppoe-wan,768:pppoe-wan"
MARKMAP=""
for e in $EXITS; do
    m_if=$(echo "$e" | cut -d'|' -f1)
    m_marks=$(echo "$e" | cut -d'|' -f4)
    [ -z "$m_if" ] && continue
    for m in $(echo "$m_marks" | tr ',' ' '); do
        [ -z "$m" ] && continue
        [ -n "$MARKMAP" ] && MARKMAP="$MARKMAP,"
        MARKMAP="$MARKMAP$m:$m_if"
    done
done

if [ -f "$IPMAP" ]; then
    HAVE_MAP=1
else
    HAVE_MAP=0
fi

awk -v lans="$LAN_NETS_RESOLVED" -v ts="$TS" -v have_map="$HAVE_MAP" -v mapfile="$IPMAP" \
    -v markmap="$MARKMAP" '
function esc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    return s
}
# 点分十进制 -> 32 位整数。用乘加而不是移位：busybox awk 没有 and()/rshift()，
# 但 double 在 2^53 以内是精确的，32 位整数完全放得下。
function ip2int(s,   a, n) {
    n = split(s, a, ".")
    if (n != 4) return -1
    return a[1]*16777216 + a[2]*65536 + a[3]*256 + a[4]
}
# 掩码可以是 "24" 也可以是 "255.255.255.0"，统一折成位数
function mask2bits(m,   a, n, bits, o, i) {
    if (m ~ /^[0-9]+$/) return m + 0
    n = split(m, a, ".")
    if (n != 4) return 32
    bits = 0
    for (i = 1; i <= 4; i++) {
        o = a[i] + 0
        if      (o >= 255) bits += 8
        else if (o >= 254) bits += 7
        else if (o >= 252) bits += 6
        else if (o >= 248) bits += 5
        else if (o >= 240) bits += 4
        else if (o >= 224) bits += 3
        else if (o >= 192) bits += 2
        else if (o >= 128) bits += 1
    }
    return bits
}
# 按网段比较高位。除法代替右移：int(v / 2^(32-bits)) 就是"截掉主机位"。
function in_lan(ip,   t, i, s) {
    t = ip2int(ip)
    if (t < 0) return 0
    for (i = 1; i <= lan_n; i++) {
        s = 2 ^ (32 - lan_bits[i])
        if (int(t / s) == int(lan_net[i] / s)) return 1
    }
    return 0
}
BEGIN {
    lan_n = 0
    m = split(lans, parts, /[ \t]+/)
    for (i = 1; i <= m; i++) {
        if (parts[i] == "") continue
        p = index(parts[i], "/")
        if (p > 0) { addr = substr(parts[i], 1, p - 1); msk = substr(parts[i], p + 1) }
        else       { addr = parts[i]; msk = 32 }
        v = ip2int(addr)
        if (v < 0) continue
        lan_n++
        lan_net[lan_n]  = v
        lan_bits[lan_n] = mask2bits(msk)
    }
    if (have_map == 1) {
        while ((getline line < mapfile) > 0) {
            n = split(line, a, /[ \t]+/)
            if (n >= 2 && a[1] != "") map[a[1]] = a[2]
        }
        close(mapfile)
    }
    if (markmap != "") {
        n = split(markmap, a, ",")
        for (i = 1; i <= n; i++) {
            split(a[i], b, ":")
            if (b[1] != "") mm[b[1]] = b[2]
        }
    }
    out = ""
    first = 1
}
{
    if ($3 != "tcp") next
    if (substr($7, 1, 4) != "src=") next
    if ($9 !~ /^sport=/ || $10 !~ /^dport=/) next

    state = $6
    src   = substr($7, 5)
    if (!in_lan(src)) next
    dst   = substr($8, 5)
    sport = substr($9, 7)
    dport = substr($10, 7)
    if (dst == "" || dport == "") next

    iface = "未知"
    mark = ""
    for (i = 11; i <= NF; i++) {
        if (substr($i, 1, 5) == "mark=") { mark = substr($i, 6); break }
    }
    if (mark in mm) iface = mm[mark]

    svc = (dst in map) ? map[dst] : "其他"

    entry = "{\"client\":\"" esc(src) "\",\"sport\":\"" esc(sport) "\",\"dst\":\"" esc(dst) "\",\"dport\":\"" esc(dport) "\",\"iface\":\"" esc(iface) "\",\"service\":\"" esc(svc) "\",\"state\":\"" esc(state) "\"}"
    if (first) { out = entry; first = 0 } else { out = out "," entry }
}
END {
    printf "{\"ts\":%s,\"streams\":[%s]}\n", ts, out
}
' /proc/net/nf_conntrack > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"

# 顺便把新配置同步给看板（tcp 周期短，配置改完几秒内看板就能读到新标题/出口名）
if [ -x /usr/bin/lm_config_json.sh ]; then
    /usr/bin/lm_config_json.sh
fi
