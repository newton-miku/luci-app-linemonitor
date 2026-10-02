LOG=/www/lm/history.log
cp "$LOG" "$LOG.bak-zero"
echo "=== 清洗前 =0,1 出现次数 ==="
tr ' ' '\n' < "$LOG" | grep -c '=0,1$'
sed -i 's/=0,1 /=FAIL,100 /g; s/=0,1$/=FAIL,100/' "$LOG"
echo "=== 清洗后 =0,1 出现次数 ==="
tr ' ' '\n' < "$LOG" | grep -c '=0,1$'
echo "=== 清洗后 FAIL,100 出现次数 ==="
tr ' ' '\n' < "$LOG" | grep -c '=FAIL,100$'
echo "=== 行数校验（应仍为 1015）==="
wc -l < "$LOG"
echo "=== 抽样：某行清洗后的 HTTP 部分 ==="
tail -n 1 "$LOG" | tr ' ' '\n' | grep -E '微信|淘宝|B站'
echo "=== 备份文件 ==="
ls -l "$LOG" "$LOG.bak-zero"