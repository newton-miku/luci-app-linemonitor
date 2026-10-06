#!/bin/sh
# 短信读取与解码，输出给 smstrun.py 判定的文本。
#
# 原厂脚本用的是 `AT+CMGL=0`（只列「未读」），但本模组收到短信落进 ME 之后就已经是
# `REC READ`，于是 `AT+CMGL=0` 恒为空，转发链路永远等不到「发件人」。改用 `AT+CMGL=4`
# 列全部，再滤掉 ^ 开头的模组主动上报（URC）。
#
# 去重：一条长短信会被模组拆成多段单独存储，**这几段的 From 和 Date/Time 完全相同**，
# 只有 `Reference number` 和 `SMS segment N of M` 不同。所以 seen 记录的键是
# 「发件人@发件时间」，值是已见过的段号集合，逐段累加。早期版本只用「发件人+发件时间」
# 做指纹，结果第一条段入库后同一条短信的其余段全被当成已推送丢掉，smstrun.py 永远
# 只收到 1 段，判定「长短信分段未齐」而不推送。
#
# 键里不能留空格：发件时间是 `10/02/26 18:04:41` 这种带空格的，下面用 awk 的 `$1`/`$2`
# 拆行取键和值，留空格的话 `$1` 会被截断、段号落到 `$3`，去重永远失配。所以空格换下划线。
#
# 四道垃圾过滤（见下面「过滤一~四」）：本模组 ME 里有一批坏槽位，
# `AT+CMGL=4` 会把它们连同末尾的 OK 一起列出来，这些行喂给 pdu_decoder 会解出乱码
# 发件人（`?7000000100000000`、`6=88<4>4:3757435?>08=?=698:5<<;88<`）和荒谬段数
# （17 段、96 段、188 段），被当成新短信推给用户。四道过滤互相独立，任何一道拦下就跳过。
#
# 不能靠「先见到 +CMGL: 头再处理 PDU」来筛：实测模组返回的**第一条 PDU 出现在第一个
# +CMGL: 头之前**（39 个头配 40 条 PDU），按头做门禁会把第一条直接丢掉，那条短信
# 永远收不到。所以只认同过十六进制校验的行，序号用自增计数器给。
#
# 副作用（预期内）：首次跑会把存储里既有的短信全部推一次。想从零开始，删掉 $SEEN 重启即可。

SEEN=${SMSTRUN_SEEN:-/etc/smstrun-seen.conf}
OUT=${SMSTRUN_OUT:-/tmp/smstrunt.at}
TMP=${SMSTRUN_TMP:-/tmp/smstruns.at}

# sendat 与 pdu_decoder 都可能被模组卡住（AT 通道忙，或 pdu_decoder 收不到换行时
# 一直挂在 read 上）。没有超时，一轮永远跑不完，而 smstrun.py 每 5 秒还会再起一轮，
# 进程越堆越多。这里统一包一层超时（本机 busybox 带 /usr/bin/timeout）。
tmo() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$@"
    else
        shift
        "$@"
    fi
}

# 测试注入点：设了 SMSTRUN_RAW_FILE 就直接读该文件的原始 AT 输出，便于在没有模组的
# 机器上验证过滤与去重（tests/test_sms_order.sh 用它）。配合上面的 SEEN/OUT/TMP 覆盖，
# 整个脚本可以完全跑在 /tmp 里，不碰真实状态。
if [ -n "$SMSTRUN_RAW_FILE" ] && [ -f "$SMSTRUN_RAW_FILE" ]; then
    rec=$(tr -d '\r' < "$SMSTRUN_RAW_FILE" | grep -v '^\^')
else
    rec=$(tmo 12 sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^')
fi

: > "$TMP"
: > "$OUT"
touch "$SEEN" 2>/dev/null

idx=''
n=0
echo "$rec" | while IFS= read -r line; do
    case "$line" in
        +CMGL:*)
            idx=$(printf '%s' "$line" | awk -F '[ ,]' '{print $2}')
            continue
            ;;
    esac

    # 模组输出偶尔带尾随空格/制表，不先去掉会被下面的十六进制校验误杀
    line=$(printf '%s' "$line" | tr -d ' \t')
    [ -n "$line" ] || continue

    # 过滤一：PDU 必须是纯十六进制。只有 +CMGL: 头没有 PDU 的空槽位、末尾的 OK、
    # AT 回显都会落到这里，这一条全挡掉（这是本次乱码轰炸的主因）。
    case "$line" in
        *[!0-9A-Fa-f]*) continue ;;
    esac
    [ ${#line} -ge 20 ] || continue

    # pdu_decoder 读到换行才返回，这里必须给一个换行，否则会一直卡在 read 上。
    pdurb=$(echo "$line" | tmo 5 pdu_decoder)
    [ -n "$pdurb" ] || continue
    idx=''
    n=$((n + 1))
    cur=$n

    frm=$(printf '%s\n' "$pdurb" | sed -n 's/^From:\(.*\)/\1/p' | tr -d '\r')
    [ -n "$frm" ] || continue

    # 过滤二：发件人只能是数字（可带前导 +）。坏槽位解出来的发件人含
    # ? = < > ; : 等字符；真号码最短是 10086 这种 5 位短号，长度下限 5。
    case "$frm" in
        *[!0-9+]*) continue ;;
    esac
    [ ${#frm} -ge 5 ] || continue

    # 过滤三：发件时间的年份必须落在 2018~2035。坏槽位的时间戳在 1990~2099
    # 之间乱跳（实测 05/31/92、12/06/99、12/29/97、08/03/64、07/31/04）。
    yy=$(printf '%s\n' "$pdurb" | sed -n 's|^Date/Time:[0-9][0-9]/[0-9][0-9]/\([0-9][0-9]\) .*|\1|p')
    yy=${yy#0}
    [ -n "$yy" ] || continue
    { [ "$yy" -ge 18 ] && [ "$yy" -le 35 ]; } || continue

    # 过滤四：段数上限 20。坏槽位解出过 `SMS segment 1 of 188`、`of 96`、`of 25`，
    # 真长短信最多十几段。
    segs=$(printf '%s\n' "$pdurb" | sed -n 's/^SMS segment [0-9][0-9]* of \([0-9][0-9]*\).*/\1/p' | head -n1)
    if [ -n "$segs" ] && [ "$segs" -gt 20 ]; then
        continue
    fi

    dtime=$(printf '%s\n' "$pdurb" | sed -n 's|^Date/Time:\(.*\)|\1|p' | tr -d '\r' | tr ' ' '_')
    key="$frm@$dtime"
    seg=$(printf '%s\n' "$pdurb" | sed -n 's/^SMS segment \([0-9][0-9]*\) of.*/\1/p' | head -n1)
    [ -n "$seg" ] || seg=0

    prev=$(awk -v k="$key" '$1 == k {print $2; exit}' "$SEEN" 2>/dev/null)
    if [ -n "$prev" ]; then
        case ",$prev," in
            *",$seg,"*) continue ;;    # 这段已经推过了
        esac
        new_segs="$prev,$seg"
        tmp2="$SEEN.tmp.$$"
        awk -v k="$key" '$1 != k' "$SEEN" > "$tmp2" 2>/dev/null || : > "$tmp2"
        printf '%s %s\n' "$key" "$new_segs" >> "$tmp2"
        mv "$tmp2" "$SEEN"
    else
        printf '%s %s\n' "$key" "$seg" >> "$SEEN"
    fi

    {
        printf '第%s条短信\n' "$cur"
        printf '%s\n' "$pdurb"
        printf -- '------------------------------------------------------\n'
    } >> "$TMP"
done

sed -e '/^Textlen=/d' \
    -e 's/^From:/发件人:/' \
    -e 's/^Date\/Time:/发件时间:/' \
    "$TMP" > "$OUT" 2>/dev/null

cat "$OUT"
