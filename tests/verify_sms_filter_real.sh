#!/bin/sh
# 逐条统计四道过滤对当前模组内容的拦截情况，确认没把真短信误杀。
S=/tmp/fstat
: > "$S"
rec=$(sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^')
idx=''
echo "$rec" | while IFS= read -r line; do
    case "$line" in
        +CMGL:*)
            idx=$(printf '%s' "$line" | awk -F '[ ,]' '{print $2}')
            echo "head" >> "$S"
            continue
            ;;
    esac
    [ -n "$idx" ] || continue
    line=$(printf '%s' "$line" | tr -d ' \t')
    [ -n "$line" ] || continue
    case "$line" in
        *[!0-9A-Fa-f]*)    echo "rej-hex" >> "$S"; continue ;;
    esac
    [ ${#line} -ge 20 ] || { echo "rej-hexlen" >> "$S"; continue; }

    pdurb=$(echo "$line" | pdu_decoder)
    idx=''
    [ -n "$pdurb" ] || { echo "rej-decode" >> "$S"; continue; }

    frm=$(printf '%s\n' "$pdurb" | sed -n 's/^From:\(.*\)/\1/p' | tr -d '\r')
    [ -n "$frm" ] || { echo "rej-empty" >> "$S"; continue; }
    case "$frm" in
        *[!0-9+]*) echo "rej-sender | $frm" >> "$S"; continue ;;
    esac
    [ ${#frm} -ge 5 ] || { echo "rej-senderlen | $frm" >> "$S"; continue; }

    yy=$(printf '%s\n' "$pdurb" | sed -n 's|^Date/Time:[0-9][0-9]/[0-9][0-9]/\([0-9][0-9]\) .*|\1|p')
    yy=${yy#0}
    [ -n "$yy" ] || { echo "rej-notime | $frm" >> "$S"; continue; }
    { [ "$yy" -ge 18 ] && [ "$yy" -le 35 ]; } || { echo "rej-year$yy | $frm" >> "$S"; continue; }

    segs=$(printf '%s\n' "$pdurb" | sed -n 's/^SMS segment [0-9][0-9]* of \([0-9][0-9]*\).*/\1/p' | head -n1)
    if [ -n "$segs" ] && [ "$segs" -gt 20 ]; then
        echo "rej-segs$segs | $frm" >> "$S"
        continue
    fi
    echo "PASS | $frm" >> "$S"
done

echo "=== 各分支计数 ==="
cut -d'|' -f1 "$S" | sort | uniq -c | sort -rn

echo
echo "=== 通过全部过滤的（发件人） ==="
grep '^PASS' "$S" | sed 's/^PASS | //' | sort | uniq -c

echo
echo "=== 被拦下的具体发件人（非纯数字的样本） ==="
grep '^rej-sender | ' "$S" | head -20

echo
echo "=== 当前 seen 里保留的键 ==="
wc -l < /etc/smstrun-seen.conf
