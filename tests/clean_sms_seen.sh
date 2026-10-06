#!/bin/sh
# 清理 seen 里修复前遗留的垃圾键，然后观察 3 分钟看它们会不会重新出现。
# 判定标准：清理后若垃圾键不再回来 → 四道过滤生效；若回来 → 过滤有漏。
SEEN=/etc/smstrun-seen.conf
BAK="/tmp/smstrun-seen.conf.bak.$(date +%s)"

cp "$SEEN" "$BAK"
echo "已备份到 $BAK"

before=$(wc -l < "$SEEN")

# 只保留「发件人 5 位以上纯数字（可带 +）」且「年份 2025~2027」的键。
# 真短信的发件人都是 10086 / 106* / 10693041407221460 这类，时间都是当前年份；
# 坏槽位解出来的是 28 / 00 / 300 / 7000700 这类短号或 1985~2099 的乱时间。
awk '{
    split($1, a, "@")
    frm = a[1]
    if (frm !~ /^\+?[0-9][0-9][0-9][0-9][0-9]+$/) next
    dt = a[2]
    split(dt, b, "/")
    if (length(b) < 3) next
    yy = b[3]
    sub(/_.*/, "", yy)
    sub(/^0/, "", yy)
    if (yy < 25 || yy > 27) next
    print
}' "$SEEN" > /tmp/seen.clean

after=$(wc -l < /tmp/seen.clean)
echo "清理前: $before 行"
echo "清理后: $after 行"

echo
echo "=== 被删掉的行 ==="
awk 'FNR==NR { keep[$0]=1; next } !($0 in keep) { print }' /tmp/seen.clean "$SEEN"

cp /tmp/seen.clean "$SEEN"
echo
echo "=== 清理后的 seen ==="
awk '{printf "%3d  %s\n", NR, $0}' "$SEEN"

echo
echo "=== 观察 180 秒，看垃圾键是否回来 ==="
i=0
while [ $i -lt 12 ]; do
    n=$(wc -l < "$SEEN")
    bad=$(awk '$1 !~ /^\+?[0-9][0-9][0-9][0-9][0-9]+@/ {n++} END {print n+0}' "$SEEN")
    echo "t=+$((i*15))s  行数=$n  非长数字发件人的行数=$bad"
    sleep 15
    i=$((i + 1))
done

echo
echo "=== 日志尾部 20 行 ==="
tail -n 20 /tmp/smstrun.log

echo
echo "=== 最终 seen ==="
awk '{printf "%3d  %s\n", NR, $0}' "$SEEN"
