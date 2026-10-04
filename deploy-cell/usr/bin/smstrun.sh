#!/bin/sh
# 短信读取与解码，输出给人看/给 smstrun.py 判定的文本。
#
# 原厂脚本用的是 `AT+CMGL=0`（只列「未读」），但本模组（+CNMI 上报模式 2,1,0,2,0
# 且 +CPMS 存在 "ME"）在实际运行中不会让新短信保持未读状态：短信落进 ME 之后
# 就已经是 `REC READ`，于是 `AT+CMGL=0` 恒为空，转发链路永远等不到「发件人」。
# 实测 `AT+CMGL=0` 只回一串 ^PDCPDATAINFO 之类的东西，而 `AT+CMGL=4` 能列出全部。
#
# 所以这里改成：
#   1. 用 `AT+CMGL=4` 列全部短信；
#   2. 滤掉 ^ 开头的模组主动上报（URC），它们会混进应答里；
#   3. 用「发件人 + 发件时间」做指纹，记在 $SEEN 里，只输出没推过的。
#
# 副作用（预期内）：第一次跑会把存储里既有的短信全部输出一次。
# 如果想从零开始，删掉 $SEEN 再重启 smstrun.py 即可。

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

    fp=$(printf '%s' "$pdurb" | grep -E '^(From|Date/Time):' | tr -d ' \r' | tr '\n' '|')
    [ -n "$fp" ] || continue
    if grep -qF "$fp" "$SEEN" 2>/dev/null; then
        continue
    fi
    printf '%s\n' "$fp" >> "$SEEN"

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
