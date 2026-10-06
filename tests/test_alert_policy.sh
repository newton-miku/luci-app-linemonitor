#!/bin/sh
# 离线验证 lm_alert.sh 的推送策略（不需要路由器，也不发真消息）
#
#   bash tests/test_alert_policy.sh
#
# 靠三件事把脚本关进沙箱：
#   1. LM_CONF / LM_LOG / LM_STATE 三个环境变量把路径指到临时目录
#   2. PATH 前面塞一个假的 curl，只把参数记进文件，不真发请求
#   3. 每个场景前清空 state，模拟"从没报过"的起点
#
# 要覆盖的策略：
#   down   连续 DEBOUNCE 次才推一条；同级不重复推；恢复推一条
#   loss   丢包/延迟越阈值才推一条；同级不重复推；恢复不推
#   升级   loss → down 立刻补推
#   阈值   丢包 < ALERT_LOSS_PCT 不报
#   冷却   ALERT_COOLDOWN > 0 时同等级会按间隔重推

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../deploy/usr/bin/lm_alert.sh"
WORK=$(mktemp -d 2>/dev/null || echo "/tmp/lmtest.$$")
mkdir -p "$WORK/bin"

[ -f "$SCRIPT" ] || { echo "找不到 $SCRIPT"; exit 1; }

# ---- 假 curl：只记录，不发网络 ----
cat > "$WORK/bin/curl" <<'MOCK'
#!/bin/sh
{
    echo "--- CURL ---"
    for a in "$@"; do echo "$a"; done
} >> "$MOCK_LOG"
MOCK
chmod +x "$WORK/bin/curl"
PATH="$WORK/bin:$PATH"
export PATH
MOCK_LOG="$WORK/push.log"
export MOCK_LOG
: > "$MOCK_LOG"

# ---- 沙箱配置 ----
cat > "$WORK/targets.conf" <<'CONF'
ALERT_ENABLE=1
ALERT_TYPE=json
ALERT_URL="http://mock.invalid/hook"
ALERT_TOKEN=""
ALERT_MAX_MS=1000
ALERT_LOSS_PCT=10
ALERT_DEBOUNCE=3
ALERT_COOLDOWN=0
ALERT_RECOVER=1
ALERT_SCOPE="all"
ALERT_IGNORE=""
CONF

export LM_CONF="$WORK/targets.conf"
export LM_LOG="$WORK/history.log"
export LM_STATE="$WORK/state"

FAILS=0
PASSES=0

# ---- 跑一轮：$1=时间戳，其余=键=值,丢包 ----
round() {
    : > "$MOCK_LOG"
    ts="$1"; shift
    printf '%s' "$ts" > "$LM_LOG"
    for kv in "$@"; do printf ' %s' "$kv" >> "$LM_LOG"; done
    printf '\n' >> "$LM_LOG"
    sh "$SCRIPT"
    PUSHED=$(grep -c -- '--- CURL ---' "$MOCK_LOG" 2>/dev/null || true)
    [ -n "$PUSHED" ] || PUSHED=0
    LAST_BODY=$(cat "$MOCK_LOG" 2>/dev/null)
}

reset_state() { rm -f "$LM_STATE"; }

check() {   # $1=期望推送条数 $2=描述
    if [ "$PUSHED" -eq "$1" ]; then
        PASSES=$((PASSES + 1))
        echo "  ok   $2 —— 推送 $PUSHED 条"
    else
        FAILS=$((FAILS + 1))
        echo "  FAIL $2 —— 期望 $1 条，实际 $PUSHED 条"
        [ -n "$LAST_BODY" ] && printf '       收到：%s\n' "$(printf '%s' "$LAST_BODY" | tr '\n' '|')"
    fi
}

check_has() {   # $1=应包含的子串 $2=描述
    case "$LAST_BODY" in
        *"$1"*) PASSES=$((PASSES + 1)); echo "  ok   $2 —— 正文含「$1」" ;;
        *) FAILS=$((FAILS + 1)); echo "  FAIL $2 —— 正文里没有「$1」" ;;
    esac
}

echo "== 场景 1：彻底断 —— 去抖 3 次后推一条，不重复，恢复再推一条 =="
reset_state
round 1000 "eth1|阿里DNS=FAIL,100"; check 0 "第 1 次 FAIL（未到去抖）"
round 1060 "eth1|阿里DNS=FAIL,100"; check 0 "第 2 次 FAIL（未到去抖）"
round 1120 "eth1|阿里DNS=FAIL,100"; check 1 "第 3 次 FAIL（到去抖，推一条）"
check_has "不可达" "标题/正文标明不可达"
round 1180 "eth1|阿里DNS=FAIL,100"; check 0 "第 4 次 FAIL（同级不重复推）"
round 1240 "eth1|阿里DNS=FAIL,100"; check 0 "第 5 次 FAIL（同级不重复推）"
round 1300 "eth1|阿里DNS=12.5,0";   check 1 "恢复正常（推一条已恢复）"
check_has "已恢复" "正文标明已恢复"

echo
echo "== 场景 2：丢包偏高 —— 推一条提醒，不重复，恢复不推 =="
reset_state
round 2000 "eth1|阿里DNS=12.5,30"; check 0 "第 1 次丢包 30%"
round 2060 "eth1|阿里DNS=12.5,30"; check 0 "第 2 次丢包 30%"
round 2120 "eth1|阿里DNS=12.5,30"; check 1 "第 3 次丢包 30%（推一条）"
check_has "质量异常" "标题标明质量异常"
round 2180 "eth1|阿里DNS=12.5,30"; check 0 "第 4 次丢包 30%（不重复推）"
round 2240 "eth1|阿里DNS=12.5,30"; check 0 "第 5 次丢包 30%（不重复推）"
round 2300 "eth1|阿里DNS=12.5,0";  check 0 "丢包恢复（不推）"

echo
echo "== 场景 3：丢包低于阈值（5% < 10%）—— 不报 =="
reset_state
round 3000 "eth1|阿里DNS=12.5,5"; check 0 "第 1 次丢包 5%"
round 3060 "eth1|阿里DNS=12.5,5"; check 0 "第 2 次丢包 5%"
round 3120 "eth1|阿里DNS=12.5,5"; check 0 "第 3 次丢包 5%（仍不报）"
round 3180 "eth1|阿里DNS=12.5,5"; check 0 "第 4 次丢包 5%（仍不报）"

echo
echo "== 场景 4：延迟超 ALERT_MAX_MS —— 归入质量异常 =="
reset_state
round 4000 "eth1|淘宝=1500.0,0"; check 0 "第 1 次延迟 1500ms"
round 4060 "eth1|淘宝=1500.0,0"; check 0 "第 2 次延迟 1500ms"
round 4120 "eth1|淘宝=1500.0,0"; check 1 "第 3 次延迟 1500ms（推一条）"
check_has "延迟" "正文标明延迟"
round 4180 "eth1|淘宝=1500.0,0"; check 0 "第 4 次延迟（不重复推）"
round 4240 "eth1|淘宝=120.0,0";  check 0 "延迟恢复（不推）"

echo
echo "== 场景 5：丢包恶化成彻底断 —— 立刻补推一条 =="
reset_state
round 5000 "eth1|阿里DNS=12.5,30"; check 0 "第 1 次丢包"
round 5060 "eth1|阿里DNS=12.5,30"; check 0 "第 2 次丢包"
round 5120 "eth1|阿里DNS=12.5,30"; check 1 "第 3 次丢包（推质量异常）"
round 5180 "eth1|阿里DNS=FAIL,100"; check 1 "变成不可达（立刻补推）"
check_has "不可达" "补推的是不可达"
round 5240 "eth1|阿里DNS=FAIL,100"; check 0 "仍不可达（不重复推）"
round 5300 "eth1|阿里DNS=12.5,0";   check 1 "恢复正常（推已恢复）"

echo
echo "== 场景 6：ALERT_COOLDOWN=3600 —— 同等级按间隔重推 =="
reset_state
sed 's/^ALERT_COOLDOWN=0/ALERT_COOLDOWN=3600/' "$WORK/targets.conf" > "$WORK/targets2.conf"
LM_CONF_SAVE="$LM_CONF"
export LM_CONF="$WORK/targets2.conf"
round 6000 "eth1|阿里DNS=FAIL,100"; check 0 "第 1 次 FAIL"
round 6060 "eth1|阿里DNS=FAIL,100"; check 0 "第 2 次 FAIL"
round 6120 "eth1|阿里DNS=FAIL,100"; check 1 "第 3 次 FAIL（首推）"
round 6180 "eth1|阿里DNS=FAIL,100"; check 0 "第 4 次 FAIL（未到冷却）"
round 9900 "eth1|阿里DNS=FAIL,100"; check 1 "冷却到期（重推一条）"
export LM_CONF="$LM_CONF_SAVE"

echo
echo "== 场景 7：多个目标同一轮出问题 —— 合并成一条 =="
reset_state
round 7000 "eth1|阿里DNS=FAIL,100 eth1|淘宝=FAIL,100"
round 7060 "eth1|阿里DNS=FAIL,100 eth1|淘宝=FAIL,100"
round 7120 "eth1|阿里DNS=FAIL,100 eth1|淘宝=FAIL,100"
check 1 "两个目标都断了（只推 1 条）"
check_has "2 项" "标题里的计数是 2"

echo
echo "== 场景 8：ALERT_SCOPE=v4 时 v6 目标不参与 =="
reset_state
sed 's/^ALERT_SCOPE="all"/ALERT_SCOPE="v4"/' "$WORK/targets.conf" > "$WORK/targets3.conf"
export LM_CONF="$WORK/targets3.conf"
round 8000 "v6-eth1|阿里v6=FAIL,100"
round 8060 "v6-eth1|阿里v6=FAIL,100"
round 8120 "v6-eth1|阿里v6=FAIL,100"
check 0 "v6 目标断了但范围是 v4（不推）"
export LM_CONF="$LM_CONF_SAVE"

echo
echo "== 场景 9：ALERT_IGNORE 命中的目标跳过 =="
reset_state
sed 's/^ALERT_IGNORE=""/ALERT_IGNORE="抖音"/' "$WORK/targets.conf" > "$WORK/targets4.conf"
export LM_CONF="$WORK/targets4.conf"
round 9000 "eth1|抖音=FAIL,100"
round 9060 "eth1|抖音=FAIL,100"
round 9120 "eth1|抖音=FAIL,100"
check 0 "抖音在忽略名单里（不推）"
export LM_CONF="$LM_CONF_SAVE"

echo
echo "== 场景 10：ALERT_ENABLE=0 时完全不动 =="
reset_state
sed 's/^ALERT_ENABLE=1/ALERT_ENABLE=0/' "$WORK/targets.conf" > "$WORK/targets5.conf"
export LM_CONF="$WORK/targets5.conf"
round 10000 "eth1|阿里DNS=FAIL,100"
round 10060 "eth1|阿里DNS=FAIL,100"
round 10120 "eth1|阿里DNS=FAIL,100"
check 0 "开关关闭（不推）"
if [ -f "$LM_STATE" ]; then
    FAILS=$((FAILS + 1)); echo "  FAIL 开关关闭时不应写状态文件"
else
    PASSES=$((PASSES + 1)); echo "  ok   开关关闭时没写状态文件"
fi
export LM_CONF="$LM_CONF_SAVE"

echo
echo "== 场景 11：--status 能读出状态 =="
reset_state
round 11000 "eth1|阿里DNS=FAIL,100"
round 11060 "eth1|阿里DNS=FAIL,100"
round 11120 "eth1|阿里DNS=FAIL,100"
ST=$(sh "$SCRIPT" --status 2>&1)
case "$ST" in
    *down*) PASSES=$((PASSES + 1)); echo "  ok   --status 显示 down" ;;
    *)      FAILS=$((FAILS + 1)); echo "  FAIL --status 没显示 down：$ST" ;;
esac

echo
echo "== 场景 12：老状态文件里的 bad 当作 down 处理 =="
reset_state
printf 'eth1|阿里DNS bad 9 1000\n' > "$LM_STATE"
round 12000 "eth1|阿里DNS=12.5,0"; check 1 "旧格式 bad 恢复 → 推已恢复"

echo
echo "------------------------------"
echo "通过 $PASSES 项，失败 $FAILS 项"
rm -rf "$WORK" 2>/dev/null
[ "$FAILS" -eq 0 ] || exit 1
exit 0
