LOG=/www/lm/history.log
echo "=== 出现 =0,1 的目标及次数 ==="
tr ' ' '\n' < "$LOG" | grep -E '=[0-9.]*,1$' | sed 's/=[^,]*,$/=/' | sort | uniq -c | sort -rn | head -20
echo
echo "=== 出现 =0,0 的目标及次数（对照）==="
tr ' ' '\n' < "$LOG" | grep -E '=0,0$' | sed 's/=[^,]*,$/=/' | sort | uniq -c | sort -rn | head -20
echo
echo "=== 全部第二字段取值分布（所有目标合计）==="
tr ' ' '\n' < "$LOG" | grep '=' | sed 's/.*,//' | sort -n | uniq -c
echo
echo "=== 首尾各一条含 =0,1 的完整日志行 ==="
grep -m1 ',1 ' "$LOG" | cut -c1-200
grep ',1 ' "$LOG" | tail -1 | cut -c1-200
echo
echo "=== 总行数与最早/最晚时间戳 ==="
wc -l < "$LOG"
head -1 "$LOG" | cut -d' ' -f1
tail -1 "$LOG" | cut -d' ' -f1