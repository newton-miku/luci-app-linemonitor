#!/bin/sh
# lm_alert.sh — 检查最近一次采集结果，把异常推送到 webhook
#
# 由 line_monitor.sh 每次采集完调用（那时 history.log 最后一行就是本轮结果），
# 也可以手动跑： lm_alert.sh          正常巡检
#              lm_alert.sh --test   立刻发一条测试消息，验证 webhook 通不通
#              lm_alert.sh --status 打印当前各目标的告警状态
#
# 去抖设计（避免每分钟轰炸一次）：
#   某个目标连续 ALERT_DEBOUNCE 次异常才推第一条；
#   推过之后保持沉默，直到恢复正常（推一条「已恢复」）或超过 ALERT_COOLDOWN 再提醒一次。
#   同一轮里多个目标异常会合并成一条消息发出去。
#
# 状态存在 /tmp（掉电即忘）。重启后如果仍然异常，会重新走一遍去抖，
# 比写进 flash 每分钟擦一次强。

. /etc/line-monitor/targets.conf

LOG=/www/lm/history.log
STATE=/tmp/lm_alert.state

# ---------------- 参数兜底 ----------------
# 老版本的 targets.conf 里没有这些字段，用默认值顶上，避免必须重装配置
: "${ALERT_ENABLE:=0}"
: "${ALERT_TYPE:=json}"
: "${ALERT_URL:=}"
: "${ALERT_TOKEN:=}"
: "${ALERT_MAX_MS:=300}"
: "${ALERT_DEBOUNCE:=3}"
: "${ALERT_COOLDOWN:=1800}"
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
            if [ "$t" = "0" ]; then
                w="-"
            else
                w=$(date -d "@$t" '+%m-%d %H:%M' 2>/dev/null) || w="$t"
            fi
            # 键最长 20 字节左右，补到 30 列
            printf '%-30s %-5s %-5s %s\n' "$k" "$s" "$c" "$w"
        done
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

TS=$(printf '%s' "$LAST" | awk '{print $1}')
case "$TS" in ''|*[!0-9]*) exit 0 ;; esac

DOWN_LIST=""; DOWN_N=0
UP_LIST="";   UP_N=0

# history.log 的每行：<ts> <键>=<值>,<状态> ... 值里没有空格
for tok in $(printf '%s' "$LAST" | awk '{for (i = 2; i <= NF; i++) print $i}'); do
    key=${tok%%=*}
    val=${tok#*=}
    ex=${key%%|*}
    tg=${key#*|}
    v=${val%%,*}
    st=${val##*,}

    in_scope "$ex" "$tg" || continue

    # 判定是否异常
    bad=0
    reason=""
    if [ "$v" = "FAIL" ]; then
        bad=1; reason="不可达"
    elif [ "$st" != "0" ]; then
        bad=1; reason="丢包 ${st}%"
    elif [ -n "$ALERT_MAX_MS" ]; then
        ms=$(printf '%s' "$v" | cut -d. -f1)
        if [ -n "$ms" ] && [ "$ms" -gt "$ALERT_MAX_MS" ] 2>/dev/null; then
            bad=1; reason="延迟 ${ms}ms（阈值 ${ALERT_MAX_MS}ms）"
        fi
    fi

    p_state=$(get_field "$key" 2)
    p_cont=$(get_field "$key" 3)
    p_push=$(get_field "$key" 4)
    [ -n "$p_cont" ] || p_cont=0
    [ -n "$p_push" ] || p_push=0

    if [ "$bad" = "1" ]; then
        cont=$((p_cont + 1))
        last_push=$p_push

        if [ "$p_state" != "bad" ]; then
            # 还没报过：连够了次数才报
            if [ "$cont" -ge "$ALERT_DEBOUNCE" ]; then
                DOWN_LIST="$DOWN_LIST
· $ex · $tg —— $reason"
                DOWN_N=$((DOWN_N + 1))
                p_state=bad
                last_push=$TS
            fi
        elif [ "$ALERT_COOLDOWN" -gt 0 ] && [ $((TS - p_push)) -ge "$ALERT_COOLDOWN" ]; then
            # 一直没好，隔一段时间再提醒一次
            DOWN_LIST="$DOWN_LIST
· $ex · $tg —— $reason（仍未恢复）"
            DOWN_N=$((DOWN_N + 1))
            last_push=$TS
        fi
        set_state "$key" "$p_state" "$cont" "$last_push"
    else
        if [ "$p_state" = "bad" ]; then
            UP_LIST="$UP_LIST
· $ex · $tg"
            UP_N=$((UP_N + 1))
        fi
        set_state "$key" ok 0 "$p_push"
    fi
done

NOW=$(date '+%m-%d %H:%M:%S')

if [ "$DOWN_N" -gt 0 ]; then
    if [ "$DOWN_N" -eq 1 ]; then
        send_alert "【线路监测】$DOWN_N 项异常" "$(printf '%s' "$DOWN_LIST" | sed '1d')
时间 $NOW"
    else
        send_alert "【线路监测】$DOWN_N 项异常" "$(printf '%s' "$DOWN_LIST" | sed '1d')
时间 $NOW"
    fi
fi

if [ "$UP_N" -gt 0 ] && [ "$ALERT_RECOVER" = "1" ]; then
    send_alert "【线路监测】$UP_N 项已恢复" "$(printf '%s' "$UP_LIST" | sed '1d')
时间 $NOW"
fi

exit 0
