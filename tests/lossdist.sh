LOG=/www/lm/history.log
echo "=== HTTP 目标(微信) 第二字段取值分布 ==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep '^eth1|微信=' | sed 's/.*,//' | sort -n | uniq -c
echo "=== ICMP 目标(阿里DNS) 第二字段取值分布 ==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep '^eth1|阿里DNS=' | sed 's/.*,//' | sort -n | uniq -c
echo "=== 电信 HTTP(微信) 第二字段分布 ==="
tail -n 400 "$LOG" | tr ' ' '\n' | grep '^pppoe-wan2|微信=' | sed 's/.*,//' | sort -n | uniq -c