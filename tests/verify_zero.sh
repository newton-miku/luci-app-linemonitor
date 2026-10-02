echo "=== 手动跑一次采集 ==="
/usr/bin/line_monitor.sh
echo "rc=$?"
echo "=== 最新一行日志 ==="
tail -n 1 /www/lm/history.log
echo "=== 该行里有没有 =0,1 脏数据 ==="
tail -n 1 /www/lm/history.log | tr ' ' '\n' | grep -c '=0,1$'
echo "=== 再跑 2 次，累计检查 ==="
/usr/bin/line_monitor.sh; /usr/bin/line_monitor.sh
tail -n 3 /www/lm/history.log | tr ' ' '\n' | grep -c '=0,1$'
echo "=== 最新 3 行里 FAIL 的条目 ==="
tail -n 3 /www/lm/history.log | tr ' ' '\n' | grep 'FAIL'