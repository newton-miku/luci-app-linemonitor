#!/bin/sh
# lm_rate.sh — 采样实时速率，写 /tmp/lm_rate.json（在 RAM 里，不磨 flash）
#
# ============================ 为什么不能只读 /proc/net/dev ============================
# 这台路由器（MTK 方案）开着 mtkhnat 硬件 NAT：已建立的连接被卸载到 PPE 硬件转发，
# 这些包**不再经过 Linux 软件接口的计数器**。实测一次 10 MB/s 的下载：
#     eth0（DSA/QDMA 父设备）  rx 10959.77 KB/s   <- 硬件路径仍计数
#     pppoe-wan2              rx     5.56 KB/s   <- 99.9% 的流量看不见
#     br-lan                  rx   513.26 KB/s
# LuCI 自带的「状态 → 实时信息」也是同一路子（/usr/bin/luci-bwc 里只有一个数据源
# 字符串 /sys/class/net/%s/statistics/%s），所以它同样会被 HNAT 绕过、同样不准。
#
# ============================ 改用 conntrack ============================
# /proc/net/nf_conntrack 里每条连接的 bytes 计数**在 HNAT 卸载后仍然更新**
# （实测 mark=768 的下载增量 = 10.7 MB/s，与 eth0.rx=8.6 MB/s 同量级），
# 而且它自带 mark=，正是 mwan3 给每个出口打的 fwmark，**直接就是出口归属**，
# 不用像解析 HNAT all_entry 的 tuple 那样去猜 WAN 那一侧是谁。
#
# 每行格式（节选）：
#   ipv4 2 tcp 6 7438 ESTABLISHED src=192.168.66.21 dst=23.212.62.96 sport=11291
#   dport=443 packets=388748 bytes=24931538 src=23.212.62.96 dst=192.168.8.115
#   sport=443 dport=11291 packets=2406842 bytes=3393407605 [ASSURED] mark=256 ...
#
#   第一个 bytes = 连接**发起方向**（内网发起就是上传）
#   第二个 bytes = **应答方向**（内网发起时就是下载），两个 packets 同理各自计数
#
# 规则：EXITS 里配了 mark 的出口走 conntrack；RATE_IFACES 里没有 mark 的接口
# （如 br-lan）仍退回接口计数。mark 不在 EXITS 里的连接（16128=0x3f00 的默认标记、
# 1024=0x400）一律丢弃，不污染任何出口的数字。
#
# ---------------- 为什么必须逐连接差分，不能按 mark 汇总 ----------------
# conntrack 的 bytes 是**每连接单调递增**的。把一个 mark 下所有连接加起来之后，
# 只要有连接关闭，这个和就会**变小**。差分得到负数 → 夹成 0 → 整个出口的速率
# 被清零（哪怕同时还有别的连接在跑）。所以状态文件按「连接五元组」逐条保存，
# 只对还活着、且上次也见过的连接求差值：
#   * 连接消失  → 不再贡献，别的连接不受影响
#   * 新连接    → 差值算 0（否则会把它的整个生命周期当成这一窗口的增量）
#
# 状态 /tmp/lm_rate_ct.state：第一行 `@<时刻>`，随后每行
#   <mark>|<src>|<sport>|<dst>|<dport>|<上传累计>|<下载累计>
# 第一次跑只记基线（速率为 0），下次才有数。
#
# 临时文件名全部带 $$（PID）：line_daemon 每 2 秒跑一次，手工排查时也会直接跑，
# 共用固定文件名会互相覆盖/删除 —— 实测表现为随机出现「有流量却报 0」。
#
# 性能：全部逻辑压在 2 个 awk 进程里（原来每出口要 fork 十几个 cut/awk，
# 实测 0.98 秒，对 2 秒的采样间隔太紧）。当前约 0.35 秒。
#
# 已知误差（都只影响单个采样窗口，会自愈）：
#   * conntrack 的 bytes 是 32 位，单条连接跑满会停在 2147483647 不再涨，
#     之后该连接增量为 0（实测大流量流未饱和；「冻结」的多半是本来就没流量的
#     空闲连接）。
#   * 两次采样之间关闭的连接，那部分字节会丢掉（长连接不受影响）。
#   * IPv6 里「外网主动连入内网」的连接方向会算反（占比很小）。

CONF=${LM_CONF:-/etc/line-monitor/targets.conf}
[ -f "$CONF" ] && . "$CONF"

RATE_IFACES=${RATE_IFACES:-"eth1 pppoe-wan2 br-lan"}
STATE=${LM_STATE:-/tmp/lm_rate.state}
CT_STATE=${LM_CT_STATE:-/tmp/lm_rate_ct.state}
# 写 /tmp（RAM）：2 秒一次的话往 overlay 上写就把 flash 磨坏了，
# CGI /cgi-bin/lm-rate 直接读这个文件。
OUT=${LM_OUT:-/tmp/lm_rate.json}

# awk 的输入文件必须存在，否则 awk 直接报错退出（首次运行时还没有 STATE）
[ -f "$STATE" ] || : > "$STATE"

now=$(date +%s)
CT=/proc/net/nf_conntrack

# ------------------------------------------------------------------ 内网网段
# 用来判断连接是谁发起的。配置里给了就用配置，留空则自动识别。
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

WORK=/tmp/lm_rate.$$
DIFF=$WORK.diff
SNAP=$WORK.snap
CT_TMP=$WORK.ctnew
STATE_TMP=$WORK.stnew
OUT_TMP=$WORK.out
# 必须逐个列全：$WORK 是目录，rm -rf 目录不会带走同名的 $WORK.snap / $WORK.diff。
# 漏删的话每 2 秒积 27 KB，tmpfs 会被撑爆。
cleanup() { rm -rf "$WORK" "$DIFF" "$SNAP" "$CT_TMP" "$STATE_TMP" "$OUT_TMP"; }
trap cleanup EXIT INT TERM
mkdir -p "$WORK"

# ------------------------------------------------- 一次读出 EXITS：接口|显示名|mark
SPEC=$(printf '%s\n' $EXITS | awk -F'|' '
    NF == 0 || $1 == "" { next }
    {
        m = $4
        gsub(/,/, " ", m)
        n = split(m, a, " ")
        c = 0
        for (i = 1; i <= n; i++) if (a[i] != "") c++
        if (c == 0) next
        s = ""
        for (i = 1; i <= n; i++) if (a[i] != "") s = s a[i] ","
        sub(/,$/, "", s)
        printf "%s:%s:%s;", $1, $2, s
    }
')

# ------------------------------------------------------------ 快照 conntrack 计数
# 输出 "<key>\t<上传累计>\t<下载累计>"，key = mark|src|sport|dst|dport
ct_ok=0
if [ -f "$CT" ]; then
    awk -v spec="$SPEC" -v lans="$(resolve_lan_nets)" -v snap="$SNAP" '
    function ip2int(s,   a, n) {
        n = split(s, a, ".")
        if (n != 4) return -1
        return a[1]*16777216 + a[2]*65536 + a[3]*256 + a[4]
    }
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
    # 比较高位，除法代替右移（busybox awk 没有 rshift/and）
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
        n = split(spec, se, ";")
        for (i = 1; i <= n; i++) {
            if (se[i] == "") continue
            c = split(se[i], f, ":")
            k = split(f[3], mm, ",")
            for (j = 1; j <= k; j++) if (mm[j] != "") wanted[mm[j]] = 1
        }
    }
    {
        nb = 0; b1 = 0; b2 = 0; mk = ""
        src = ""; dst = ""; sp = ""; dp = ""
        for (i = 1; i <= NF; i++) {
            p = index($i, "=")
            if (p < 2) continue
            f = substr($i, 1, p - 1)
            v = substr($i, p + 1)
            if      (f == "bytes") { nb++; if (nb == 1) b1 = v + 0; else b2 = v + 0 }
            else if (f == "mark")  { mk = v + 0 }
            else if (f == "src")   { if (src == "") src = v }
            else if (f == "dst")   { if (dst == "") dst = v }
            else if (f == "sport") { if (sp  == "") sp  = v }
            else if (f == "dport") { if (dp  == "") dp  = v }
        }
        if (!(mk in wanted)) next
        if (src == "" || dst == "") next
        # 内网发起：第一个 bytes 是上传；外网主动连入内网则相反
        if (in_lan(dst) && !in_lan(src)) { u = b2; d = b1 }
        else                              { u = b1; d = b2 }
        # key 用 | 分隔，地址本身不含 |，IPv6 的冒号也不影响
        printf "%s|%s|%s|%s|%s\t%.0f\t%.0f\n", mk, src, sp, dst, dp, u, d > snap
    }
    ' "$CT" 2>/dev/null
    if [ -s "$SNAP" ]; then ct_ok=1; fi
fi

# --------------------------------- 逐连接差分 → <mark> <下载字节/秒> <上传字节/秒>
if [ "$ct_ok" = "1" ] && [ -s "$CT_STATE" ]; then
    awk -v now="$now" '
    FNR == 1 && substr($1, 1, 1) == "@" { pts = substr($1, 2) + 0; next }
    FILENAME == ARGV[1] { pu[$1] = $2; pd[$1] = $3; next }
    { cu[$1] = $2; cd[$1] = $3 }
    END {
        dt = now - pts
        if (dt <= 0) exit
        for (k in cu) {
            if (!(k in pu)) continue       # 新连接不计（否则整个生命周期算进本窗口）
            du = cu[k] - pu[k]
            dd = cd[k] - pd[k]
            if (du < 0) du = 0
            if (dd < 0) dd = 0
            split(k, p, "|")
            m = p[1]
            up[m] += du
            dn[m] += dd
        }
        for (m in up) printf "%s %.0f %.0f\n", m, dn[m] / dt, up[m] / dt
    }
    ' "$CT_STATE" "$SNAP" > "$DIFF" 2>/dev/null
fi

# 覆盖 conntrack 基线（无论有没有旧状态都写，保证下次一定有基线）
if [ "$ct_ok" = "1" ]; then
    { echo "@$now"; cat "$SNAP"; } > "$CT_TMP"
    mv "$CT_TMP" "$CT_STATE"
fi

# ------------------------------------------------------------- 组装 JSON（一个 awk）
awk -v now="$now" -v spec="$SPEC" -v order="$RATE_IFACES" -v diff="$DIFF" \
    -v ctok="$ct_ok" -v state="$STATE" -v out="$OUT" -v stmp="$STATE_TMP" '
function esc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    return s
}
BEGIN {
    # spec -> label[iface], marklist[iface]
    n = split(spec, se, ";")
    for (i = 1; i <= n; i++) {
        if (se[i] == "") continue
        split(se[i], f, ":")
        if (f[1] == "") continue
        label[f[1]] = f[2]
        marks[f[1]] = f[3]
    }
    # 接口计数：read_state 里载入上次的 <接口> <rx> <tx> <时刻>
    n = split(diff, dl, "\n")
    for (i = 1; i <= n; i++) {
        if (dl[i] == "") continue
        split(dl[i], a, " ")
        m = a[1]
        dm[m] = a[2] + 0
        um[m] = a[3] + 0
    }
}
# --- 第 1 个文件：接口旧计数 ---
FILENAME == state {
    if ($1 != "") { prx[$1] = $2 + 0; ptx[$1] = $3 + 0; pts[$1] = $4 + 0 }
    next
}
# --- 第 2 个文件：/proc/net/dev ---
{
    line = $0
    sub(/^[ \t]+/, "", line)
    ci = index(line, ":")
    if (ci == 0) next
    name = substr(line, 1, ci - 1)
    gsub(/[ \t]/, "", name)
    split(substr(line, ci + 1), f, " ")
    crx[name] = f[1] + 0
    ctx[name] = f[9] + 0
    next
}
END {
    no = split(order, ol, " ")
    json = ""
    sep = ""
    st = ""
    for (i = 1; i <= no; i++) {
        iface = ol[i]
        if (iface == "") continue
        lbl = (iface in label) ? label[iface] : iface
        rxs = 0
        txs = 0
        have = 0
        # --- 有 mark 的接口：走 conntrack ---
        if (ctok == "1" && (iface in marks)) {
            mk = split(marks[iface], mm, ",")
            for (j = 1; j <= mk; j++) {
                m = mm[j]
                if (m in dm) { rxs += dm[m]; txs += um[m]; have = 1 }
            }
        }
        # --- 无 mark 的接口：退回 /proc/net/dev 差分 ---
        if (have == 0 && (iface in crx)) {
            if ((iface in prx) && (iface in pts)) {
                dt = now - pts[iface]
                if (dt <= 0) dt = 1
                d = crx[iface] - prx[iface]
                if (d < 0) d = 0
                rxs = int(d / dt)
                d = ctx[iface] - ptx[iface]
                if (d < 0) d = 0
                txs = int(d / dt)
            }
            st = st sprintf("%s %.0f %.0f %d\n", iface, crx[iface], ctx[iface], now)
        }
        json = json sep sprintf("{\"if\":\"%s\",\"label\":\"%s\",\"rx\":%.0f,\"tx\":%.0f}",
                                esc(iface), esc(lbl), rxs, txs)
        sep = ","
    }
    printf "{\"ts\":%d,\"rates\":[%s]}\n", now, json > out
    printf "%s", st > stmp
}
' "$STATE" /proc/net/dev 2>/dev/null
if [ -s "$STATE_TMP" ]; then
    mv "$STATE_TMP" "$STATE"
fi