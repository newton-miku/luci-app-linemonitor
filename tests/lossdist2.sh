LOG=/www/lm/history.log
echo "=== 含 wan|微信=...,1 的原始行（最多 5 行）==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep -E '^wan\|微信=[0-9.]+,1$' | head -5
echo "=== 含 wan|微信=FAIL 的行（最多 5 行）==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep -E '^wan\|微信=FAIL,1$' | head -5
echo "=== 统计: 微信=FAIL,1 出现次数 ==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep -cE '^wan\|微信=FAIL,1$'
echo "=== 完整一行样本（最后 3 行原始日志，截取含微信的部分）==="
tail -n 3 "$LOG" | tr ' ' '\n' | grep -E '微信|阿里DNS'