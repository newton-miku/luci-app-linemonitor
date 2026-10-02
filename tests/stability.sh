#!/bin/sh
# 连跑 5 次采集，检查移动出口 HTTP 目标的失败率
i=1
while [ $i -le 5 ]; do
    sh /usr/bin/line_monitor.sh
    i=$((i + 1))
done
echo "=== 最后 5 行里 eth1 各目标的成败统计 ==="
tail -n 5 /www/lm/history.log | tr ' ' '\n' | grep '^eth1|' | sort | uniq -c | sort -k2
echo
echo "=== 最后 5 行里 v6-eth1 ==="
tail -n 5 /www/lm/history.log | tr ' ' '\n' | grep '^v6-eth1|' | sort | uniq -c | sort -k2
