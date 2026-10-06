#!/bin/sh
# lm_alert.sh — 检查最近一次采集结果，把异常推送到 webhook
#
# 由 line_monitor.sh 每次采集完调用（那时 history.log 最后一行就是本轮结果），
# 也可以手动跑： lm_alert.sh          正常巡检
#              lm_alert.sh --test   立刻发一条测试消息，验证 webhook 通不通
#              lm_alert.sh --status 打印当前各目标的告警状态
#
# 去抖设计（避免每分钟轰炸一次）：
#   异常分两级，各自独立去抖、各自只推一条：
#     down  彻底不可达（ping 全丢 / curl 连不上）—— 线路断了
#     loss  能通但质量差（丢包 ≥ ALERT_LOSS_PCT，或延迟 > ALERT_MAX_MS）
#   某个目标连续 ALERT_DEBOUNCE 次处于同一级才推第一条；推过之后保持沉默，
#   同级不再重复推（ALERT_COOLDOWN=0），除非显式设了重发间隔。
#   升级（loss → down）会补推一条；降级（down → loss）算「线路回来了」，
#   按恢复处理（此时还没完全好，正文里会注明仍有丢包）。
#   恢复：只有 down 变正常才推「已恢复」，loss 变正常不推 —— 丢包抖动太频繁，
#   报恢复只会更吵。ALERT_RECOVER=0 可整体关掉恢复推送。
#   同一轮里同类多个目标会合并成一条消息发出去。
#
# 状态存在 /tmp（掉电即忘）。重启后如果仍然异常，会重新走一遍去抖，
# 比写进 flash 每分钟擦一次强。

# 路径可以用环境变量覆盖，方便离线测试（tests/test_alert_policy.sh 就是这么跑的）
CONF=${LM_CONF:-/etc/line-monitor/targets.conf}
[ -f "$CONF" ] && . "$CONF"

LOG=${LM_LOG:-/www/lm/history.log}
STATE=${LM_STATE:-/tmp/lm_alert.state}

# ---------------- 参数兜底 ----------------
# 老版本的 targets.conf 里没有这些字段，用默认值顶上，避免必须重装配置
: "${ALERT_ENABLE:=0}"
: "${ALERT_TYPE:=json}"
: "${ALERT_URL:=}"
: "${ALERT_TOKEN:=}"
: "${ALERT_MAX_MS:=1000}"
: "${ALERT_LOSS_PCT:=10}"
: "${ALERT_DEBOUNCE:=3}"
: "${ALERT_COOLDOWN:=0}"
: "${ALERT_RECOVER:=1}"
: "${ALERT_SCOPE:=v4}"
: "${ALERT_IGNORE:=}"

# ---------------- 小工具 ----------------

# 把文本转成能塞进 JSON 字符串的形式（转义 \ 和 "，换行写成 \n）
json_esc() {
    awk 'BEGIN{ORS=""} {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        if (NR > 1) printf "\\n"
        printf "%s", $0
    }'
}

# 状态读写：每行 "<键> <状态> <连续次数> <上次推送时间>"，键里没有空格
get_field() {   # $1=键 $2=字段号(2|3|4)，找不到输出默认值
    awk -v k="$1" -v f="$2" '
        $1 == k { print $f; found = 1; exit }
        END { if (!found) print (f == 2 ? "ok" : "0") }
    ' "$STATE" 2>/dev/null
}

set_state() {   # $1=键 $2=状态 $3=连续 $4=上次推送
    awk -v k="$1" -v s="$2" -v c="$3" -v t="$4" '
        $1 == k { print k, s, c, t; done = 1; next }
        { print }
        END { if (!done) print k, s, c, t }
    ' "$STATE" 2>/dev/null > "$STATE.tmp"
    mv "$STATE.tmp" "$STATE"
}

# ---------------- 推送 ----------------
# 按 ALERT_TYPE 组装请求。$1=标题 $2=正文
send_alert() {
    local title="$1" body="$2"
    local full="$title
$body"
    case "$ALERT_TYPE" in
        bark)
            # https://api.day.app/<key>/<标题>/<正文>，key 填在 URL 里或 ALERT_TOKEN
            local base="${ALERT_URL:-https://api.day.app}"
            curl -s -m 10 -o /dev/null \
                "$base/$(printf '%s' "$title" | awk '{gsub(/ /,"%20"); print}')/$(printf '%s' "$body" | awk '{gsub(/ /,"%20"); gsub(/\n/,"%0A"); print}')"
            ;;
        wecom|dingtalk)
            # 企业微信 / 钉钉：{"msgtype":"text","text":{"content":"..."}}
            local url="$ALERT_URL"
            [ -n "$ALERT_TOKEN" ] && url="$ALERT_URL$ALERT_TOKEN"
            curl -s -m 10 -o /dev/null -X POST -H 'Content-Type: application/json' \
                -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$(printf '%s' "$full" | json_esc)\"}}" "$url"
            ;;
        feishu)
            # 飞书：{"msg_type":"text","content":{"text":"..."}}
            curl -s -m 10 -o /dev/null -X POST -H 'Content-Type: application/json' \
                -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"$(printf '%s' "$full" | json_esc)\"}}" "$ALERT_URL"
            ;;
        serverchan)
            # Server 酱：表单 POST，title + desp
            curl -s -m 10 -o /dev/null -X POST \
                --data-urlencode "title=$title" --data-urlencode "desp=$body" "$ALERT_URL"
            ;;
        telegram)
            # ALERT_TOKEN = bot token，ALERT_URL = chat_id
            curl -s -m 10 -o /dev/null -X POST -H 'Content-Type: application/json' \
                -d "{\"chat_id\":\"$ALERT_URL\",\"text\":\"$(printf '%s' "$full" | json_esc)\"}" \
                "https://api.telegram.org/bot$ALERT_TOKEN/sendMessage"
            ;;
        *)
            # json：通用 POST，自定义 URL，正文 {"title":...,"text":...}
            curl -s -m 10 -o /dev/null -X POST -H 'Content-Type: application/json' \
                -d "{\"title\":\"$(printf '%s' "$title" | json_esc)\",\"text\":\"$(printf '%s' "$body" | json_esc)\"}" \
                "$ALERT_URL"
            ;;
    esac
}

# 是否要把这个键纳入监测
in_scope() {    # $1=出口(可能带 v6- 前缀)  $2=目标名
    local ex="$1" tg="$2" raw="$1|$2"
    # ALERT_IGNORE 里可以写 "目标名" 或 "出口|目标"，按空格分隔
    for ig in $ALERT_IGNORE; do
        if [ "$ig" = "$tg" ] || [ "$ig" = "$raw" ] || [ "$ig" = "$ex" ]; then
            return 1
        fi
    done
    case "$ALERT_SCOPE" in
        v4)  case "$ex" in v6-*) return 1 ;; esac ;;
        v6)  case "$ex" in v6-*) ;; *) return 1 ;; esac ;;
    esac
    return 0
}

[ "$ALERT_ENABLE" = "1" ] || [ "${1#--}" != "$1" ] || exit 0

# ---------------- --test：直接发一条 ----------------
if [ "$1" = "--test" ]; then
    if [ -z "$ALERT_URL" ] && [ "$ALERT_TYPE" != "bark" ]; then
        echo "未配置 ALERT_URL" >&2
        exit 1
    fi
    send_alert "【线路监测】测试消息" "如果你看到这条，说明 webhook 配好了。
路由器 $(cat /proc/sys/kernel/hostname 2>/dev/null)
时间 $(date '+%m-%d %H:%M:%S')"
    echo "已尝试推送（$ALERT_TYPE）。没有收到就检查 URL / token / 网络。"
    exit 0
fi

# ---------------- --status：打印状态表 ----------------
if [ "$1" = "--status" ]; then
    if [ -s "$STATE" ]; then
        # 手工对齐：printf 的 %-30s 按字节数补空格，中文一个字两字节，表头会歪
        echo "出口|目标                     状态  连续  上次推送"
        awk '{print $1, $2, $3, $4}' "$STATE" | while read -r k s c t; do
            [ "$s" = "bad" ] && s=down   # 老状态文件里的 bad 等于 down
            if [ "$t" = "0" ]; then
                w="-"
            else
                w=$(date -d "@$t" '+%m-%d %H:%M' 2>/dev/null) || w="$t"
            fi
            # 键最长 20 字节左右，补到 30 列
            printf '%-30s %-5s %-5s %s\n' "$k" "$s" "$c" "$w"
        done
        echo "(状态：ok 正常 / down 不可达 / loss 丢包或延迟偏高)"
    else
        echo "还没有任何状态记录"
    fi
    exit 0
fi

[ "$ALERT_ENABLE" = "1" ] || exit 0

# ---------------- 正常巡检 ----------------
[ -f "$LOG" ] || exit 0
LAST=$(tail -n 1 "$LOG")
[ -n "$LAST" ] || exit 0

# 状态文件必须先存在：awk 打不开输入文件时会直接退出、不跑 END 块，
# 于是 set_state 的第一次写入会落进一个空文件，状态凭空丢掉。
[ -f "$STATE" ] || : > "$STATE"

TS=$(printf '%s' "$LAST" | awk '{print $1}')
case "$TS" in ''|*[!0-9]*) exit 0 ;; esac

DOWN_LIST=""; DOWN_N=0    # 彻底不可达
LOSS_LIST=""; LOSS_N=0    # 丢包 / 延迟偏高
UP_LIST="";   UP_N=0      # 恢复（只统计 down 恢复）

# history.log 的每行：<ts> <键>=<值>,<状态> ... 值里没有空格
for tok in $(printf '%s' "$LAST" | awk '{for (i = 2; i <= NF; i++) print $i}'); do
    key=${tok%%=*}
    val=${tok#*=}
    ex=${key%%|*}
    tg=${key#*|}
    v=${val%%,*}
    st=${val##*,}

    in_scope "$ex" "$tg" || continue

    # 分级：down 彻底不通 / loss 能通但质量差 / ok 正常
    level=ok
    reason=""
    if [ "$v" = "FAIL" ]; then
        level=down; reason="不可达"
    elif [ -n "$st" ] && [ "$st" != "0" ] && [ "$st" -ge "$ALERT_LOSS_PCT" ] 2>/dev/null; then
        level=loss; reason="丢包 ${st}%"
    elif [ -n "$ALERT_MAX_MS" ]; then
        ms=$(printf '%s' "$v" | cut -d. -f1)
        if [ -n "$ms" ] && [ "$ms" -gt "$ALERT_MAX_MS" ] 2>/dev/null; then
            level=loss; reason="延迟 ${ms}ms（阈值 ${ALERT_MAX_MS}ms）"
        fi
    fi

    p_state=$(get_field "$key" 2)
    p_cont=$(get_field "$key" 3)
    p_push=$(get_field "$key" 4)
    [ -n "$p_cont" ] || p_cont=0
    [ -n "$p_push" ] || p_push=0
    [ -n "$p_state" ] || p_state=ok
    # 老状态文件里异常一律写 bad，按 down 处理
    case "$p_state" in bad) p_state=down ;; esac

    if [ "$level" != "ok" ]; then
        cont=$((p_cont + 1))
        last_push=$p_push

        if [ "$p_state" = "ok" ]; then
            # 由正常转异常：连够 DEBOUNCE 次才推第一条
            if [ "$cont" -ge "$ALERT_DEBOUNCE" ]; then
                if [ "$level" = "down" ]; then
                    DOWN_LIST="$DOWN_LIST
· $ex · $tg —— $reason"
                    DOWN_N=$((DOWN_N + 1))
                else
                    LOSS_LIST="$LOSS_LIST
· $ex · $tg —— $reason"
                    LOSS_N=$((LOSS_N + 1))
                fi
                p_state=$level
                last_push=$TS
            fi
        elif [ "$p_state" != "$level" ]; then
            # 等级变了
            if [ "$level" = "down" ]; then
                # 丢包恶化成彻底不可达：不等去抖，立刻补一条
                DOWN_LIST="$DOWN_LIST
· $ex · $tg —— $reason"
                DOWN_N=$((DOWN_N + 1))
            else
                # down → loss：连通恢复了但还没好干净，按恢复推一条
                UP_LIST="$UP_LIST
· $ex · $tg（已恢复连通，仍有丢包）"
                UP_N=$((UP_N + 1))
            fi
            p_state=$level
            last_push=$TS
        elif [ "$ALERT_COOLDOWN" -gt 0 ] && [ $((TS - p_push)) -ge "$ALERT_COOLDOWN" ]; then
            # 同等级一直没好转，且显式设了重发间隔才再提醒一次
            if [ "$level" = "down" ]; then
                DOWN_LIST="$DOWN_LIST
· $ex · $tg —— $reason（仍未恢复）"
                DOWN_N=$((DOWN_N + 1))
            else
                LOSS_LIST="$LOSS_LIST
· $ex · $tg —— $reason（仍未好转）"
                LOSS_N=$((LOSS_N + 1))
            fi
            last_push=$TS
        fi
        set_state "$key" "$p_state" "$cont" "$last_push"
    else
        # 恢复正常：只有「彻底断过」才值得报一条，丢包抖动不报恢复
        if [ "$p_state" = "down" ]; then
            UP_LIST="$UP_LIST
· $ex · $tg"
            UP_N=$((UP_N + 1))
        fi
        set_state "$key" ok 0 "$p_push"
    fi
done

NOW=$(date '+%m-%d %H:%M:%S')

if [ "$DOWN_N" -gt 0 ]; then
    send_alert "【线路监测】$DOWN_N 项不可达" "$(printf '%s' "$DOWN_LIST" | sed '1d')
时间 $NOW"
fi

if [ "$LOSS_N" -gt 0 ]; then
    send_alert "【线路监测】$LOSS_N 项质量异常" "$(printf '%s' "$LOSS_LIST" | sed '1d')
时间 $NOW"
fi

if [ "$UP_N" -gt 0 ] && [ "$ALERT_RECOVER" = "1" ]; then
    send_alert "【线路监测】$UP_N 项已恢复" "$(printf '%s' "$UP_LIST" | sed '1d')
时间 $NOW"
fi

exit 0
