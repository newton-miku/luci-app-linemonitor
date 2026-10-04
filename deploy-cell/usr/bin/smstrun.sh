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
# 副作用（预期内）：首次跑会把存储里既有的短信全部推一次。想从零开始，删掉 $SEEN 重启即可。

SEEN=/etc/smstrun-seen.conf
OUT=/tmp/smstrunt.at
TMP=/tmp/smstruns.at

rec=$(sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^')

: > "$TMP"
: > "$OUT"
touch "$SEEN" 2>/dev/null

idx=''
echo "$rec" | while IFS= read -r line; do
    case "$line" in
        +CMGL:*)
            idx=$(printf '%s' "$line" | awk -F '[ ,]' '{print $2}')
            continue
            ;;
    esac
    [ -n "$idx" ] || continue
    [ -n "$line" ] || continue

    # pdu_decoder 读到换行才返回，这里必须给一个换行，否则会一直卡在 read 上。
    pdurb=$(echo "$line" | pdu_decoder)
    cur=$idx
    idx=''
    [ -n "$pdurb" ] || continue

    frm=$(printf '%s\n' "$pdurb" | sed -n 's/^From:\(.*\)/\1/p' | tr -d '\r')
    # 发件人为空的是模组里的测试/垃圾 PDU（时间戳像 07/03/41、11/30/99），直接跳过
    [ -n "$frm" ] || continue
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
