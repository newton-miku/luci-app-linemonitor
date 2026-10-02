#!/bin/sh
# line_monitor.sh — 每 INTERVAL_MONITOR 秒采集各出口到各目标的延迟，追加到 /www/lm/history.log
#
# 出口、目标、参数全部来自 /etc/line-monitor/targets.conf，这里不写死任何出口。
# 踩坑注意:
#   1. 有的出口测 HTTP 目标前要临时加源地址策略路由（配置里填了「源IP」才需要），测完删除
#   2. 系统 DNS 走 tailscale 解析不了公网域名，须显式 nslookup <域名> $PUBLIC_DNS
#   3. busybox sed/awk 正则坑：解析 ping 输出用 awk index()+split()，不用 sed
#   4. 变量别叫 ip，会把 ip 命令遮蔽掉，后面调用 ip rule 就废了

. /etc/line-monitor/targets.conf

LOG=/www/lm/history.log
IPMAP=/tmp/lm_ipmap.txt

mkdir -p /www/lm /tmp

# 解析单个域名 -> 首个 IP（显式公网 DNS，兼容 "Address N:" 输出）
resolve_ip() {
    nslookup "$1" "$PUBLIC_DNS" 2>/dev/null | awk '/^Address [0-9]+: /{print $3; exit}'
}

# 重建 域名->IP 映射缓存（供 tcp_stream.sh 识别服务名）
# 一个域名常解析出多个 IP（CDN），全部记入；只收首个会让大量连接被判成"其他"
rebuild_ipmap() {
    : > "$IPMAP"
    for t in $HTTP_TARGETS; do
        name=${t%%:*}; host=${t#*:}
        nslookup "$host" "$PUBLIC_DNS" 2>/dev/null |
            awk -v n="$name" '/^Address [0-9]+: /{print $3, n}' >> "$IPMAP"
    done
}

# 刷新看板的 config.json（标题、出口显示名）。生成逻辑单独成脚本，
# 采集脚本和配置页共用同一份，避免两处实现漂移。
refresh_dashboard_config() {
    [ -x /usr/bin/lm_config_json.sh ] && /usr/bin/lm_config_json.sh
}

# 读接口的全局 IPv6 源地址（后面 ping6 用它，不是用接口名）
#
# 为什么不能用接口名：本固件 busybox 1.33 的 `ping6 -I pppoe-wan2` 一律报
# "sendto: Permission denied" —— 那是 PPPoE 点对点接口，SO_BINDTODEVICE 绑不上。
# 换成 `ping6 -I <该接口的全局 IPv6 地址>` 立刻就通（实测 28ms 0% 丢包）。
# 而 IPv6 路由表里每个出口的默认路由本来就带 `from <前缀>`：
#     default from 2409:8970:9d31:4f78::/64 via ... dev eth1      metric 384
#     default from 240e:358:a001:e066::/64 via ... dev pppoe-wan2 metric 512
# 所以源地址一选定，内核自己就选对出口了，根本不需要绑设备。
#
# 前缀由运营商下发、会变，所以跟 v4 的 auto 一样必须现读，不能写死。
# tailscale0 的 fd7a::/128 是 ULA，判掉；链路本地 fe80:: 也不是出口地址。
v6_src_of() {
    ip -6 addr show dev "$1" scope global 2>/dev/null |
        awk '/inet6 /{sub(/\/.*/,"",$2); if ($2 !~ /^f[cd]/) { print $2; exit }}'
}

# ping 解析: 从输出提取 avg 与 loss(%)，失败返回 "FAIL 100"
ping_parse() {
    # $1=接口 $2=IP
    local out avg loss
    out=$(ping -I "$1" -c "$PING_COUNT" -W 2 "$2" 2>/dev/null)
    [ $? -ne 0 ] && [ -z "$out" ] && { echo "FAIL 100"; return; }
    # busybox ping 尾部: "3 packets transmitted, 3 packets received, 0% packet loss"
    # 或 "... 100% packet loss"
    loss=$(echo "$out" | awk '/packet loss/{n=split($0,a,", "); for(i=1;i<=n;i++) if(index(a[i],"% packet loss")){split(a[i],b," "); sub(/%/,"",b[1]); print b[1]; exit}}')
    [ -z "$loss" ] && loss=100
    if [ "$loss" = "100" ]; then
        echo "FAIL 100"
    else
        # 尾部: "round-trip min/avg/max = 24.1/25.4/26.3 ms"
        avg=$(echo "$out" | awk '/round-trip/{n=split($0,a,"/"); print a[n-1]}')
        [ -z "$avg" ] && avg=0
        echo "$avg $loss"
    fi
}

# ping6 解析（同 ping）
ping6_parse() {
    local out avg loss
    out=$(ping6 -I "$1" -c "$PING_COUNT" -W 2 "$2" 2>/dev/null)
    [ $? -ne 0 ] && [ -z "$out" ] && { echo "FAIL 100"; return; }
    loss=$(echo "$out" | awk '/packet loss/{n=split($0,a,", "); for(i=1;i<=n;i++) if(index(a[i],"% packet loss")){split(a[i],b," "); sub(/%/,"",b[1]); print b[1]; exit}}')
    [ -z "$loss" ] && loss=100
    if [ "$loss" = "100" ]; then
        echo "FAIL 100"
    else
        avg=$(echo "$out" | awk '/round-trip/{n=split($0,a,"/"); print a[n-1]}')
        [ -z "$avg" ] && avg=0
        echo "$avg $loss"
    fi
}

# curl 测 TCP 连接耗时（忽略 HTTP 层空响应，握手成功即算连通）
# 返回 "耗时ms 0" 或 "FAIL 1"
curl_parse() {
    # $1=接口 $2=IP $3=原始域名（用于 Host 头，可为空）
    local ms rc
    if [ -n "$3" ]; then
        ms=$(curl --interface "$1" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CURL_TIMEOUT" -H "Host: $3" "http://$2" 2>/dev/null)
    else
        ms=$(curl --interface "$1" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CURL_TIMEOUT" "http://$2" 2>/dev/null)
    fi
    # 光看输出分不出「真的 0ms」和「压根没连上」——curl 失败时 -w 照样打 0.000000，
    # 必须靠退出码判断，否则失败会被记成合法的 0ms，曲线被画成一条假零线。
    # rc=52（服务器空回复）和 56（接收失败）发生在握手之后：目标站点按 Host 头
    # 决定要不要应答（QQ 就是），此时 time_connect 已经测到，不算线路故障。
    rc=$?
    case "$rc" in
        0|52|56) ;;
        *) echo "FAIL 1"; return ;;
    esac
    # rc=52/56 时 curl 可能压根不填 -w，$ms 会是空串——直接过 awk 会算出 "0 1"，
    # 看板把 0 当合法 0ms 画在底部（真机实测移动侧四个 HTTP 目标各有 500+ 条这种脏数据）。
    # 连接耗时不可能真的是 0，所以值 <= 0 一律按失败记。
    # 0.041234 -> 41
    echo "$ms" | awk '{ if ($1 + 0 <= 0) { printf "FAIL 1\n" } else { printf "%d 0\n", $1*1000 } }'
}

# 追加一个 出口|目标=值,状态 到结果串
append_result() {
    # $1=结果串(引用) $2=出口键 $3=目标名 $4=值 $5=状态
    eval "$1=\"\$$1 $2|$3=$4,$5\""
}

RESULT=""
TS=$(date +%s)

rebuild_ipmap
refresh_dashboard_config

# ---- 逐个出口、逐个目标测一遍 ----
for e in $EXITS; do
    EX_IF=$(echo "$e" | cut -d'|' -f1)
    [ -z "$EX_IF" ] && continue
    EX_SRC=$(echo "$e" | cut -d'|' -f3)
    # 第 5 字段是类型：v4 只测 IPv4、v6 只测 IPv6、both 都测。
    # 留空或写错都按 both 算，这样老配置不加字段也不会漏测。
    EX_TYPE=$(echo "$e" | cut -d'|' -f5)
    case "$EX_TYPE" in
        v4|v6) ;;
        *) EX_TYPE="both" ;;
    esac

    # 源地址策略路由（测 HTTP 目标用，测完删掉）
    #   auto = 取接口当前地址。DHCP 出口必须这样：写死的地址一旦续租变了，
    #          规则还挂在那儿却不匹配任何流量，包从本接口出去、回包按主表默认
    #          路由回来，非对称路由会让 TCP 握手随机失败（表现为 HTTP 目标时通时不通）。
    #   留空 = 不加规则（PPPoE 这类自带出口路由的接口不需要）
    rule_tbl=""
    if [ "$EX_SRC" = "auto" ]; then
        EX_SRC=$(ip -4 addr show "$EX_IF" 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
    fi
    if [ -n "$EX_SRC" ]; then
        # 表号也要按接口推，硬编码 lookup 1 会把别的出口的流量塞进移动的表
        for tb in 1 2 3 4 5; do
            if ip route show table "$tb" 2>/dev/null | grep -q "dev $EX_IF"; then
                rule_tbl=$tb
                break
            fi
        done
    fi
    rule_added=0
    if [ -n "$EX_SRC" ] && [ -n "$rule_tbl" ]; then
        ip rule add from "$EX_SRC" lookup "$rule_tbl" pref 3000 2>/dev/null && rule_added=1
    fi

    if [ "$EX_TYPE" != "v6" ]; then
        # ICMP 类（DNS）
        for t in $ICMP_TARGETS; do
            name=${t%%:*}; host=${t#*:}
            tip=$(resolve_ip "$host")
            [ -z "$tip" ] && tip="$host"   # 本身就是 IP 则直接用
            res=$(ping_parse "$EX_IF" "$tip")
            append_result RESULT "$EX_IF" "$name" $res
        done

        # HTTP 类（网站/游戏）
        for t in $HTTP_TARGETS; do
            name=${t%%:*}; host=${t#*:}
            tip=$(resolve_ip "$host")
            [ -z "$tip" ] && tip="$host"
            res=$(curl_parse "$EX_IF" "$tip" "$host")
            append_result RESULT "$EX_IF" "$name" $res
        done
    fi

    if [ "$EX_TYPE" != "v4" ]; then
        # IPv6 类：源地址现读（见 v6_src_of 的注释），取不到就整组记 FAIL
        v6src=$(v6_src_of "$EX_IF")
        for t in $ICMP6_TARGETS; do
            name=${t%%:*}; tip=${t#*:}
            if [ -n "$v6src" ]; then
                res=$(ping6_parse "$v6src" "$tip")
            else
                res="FAIL 100"
            fi
            append_result RESULT "v6-$EX_IF" "$name" $res
        done
    fi

    if [ "$rule_added" = "1" ]; then
        ip rule del from "$EX_SRC" lookup "$rule_tbl" pref 3000 2>/dev/null
    fi
done

# ---- 写入历史（保留 KEEP_LINES 行）----
echo "$TS$RESULT" >> "$LOG"
tail -n "$KEEP_LINES" "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"

# ---- 异常推送 ----
# 放在写日志之后：lm_alert.sh 读的就是 history.log 的最后一行。
# 独立成脚本，既能手动跑（--test / --status），也免得推送逻辑拖慢采集主流程。
[ -x /usr/bin/lm_alert.sh ] && /usr/bin/lm_alert.sh >/dev/null 2>&1

exit 0
