#!/bin/sh
# 看 v6 目标在 history.log 里的最新状态
echo "===== 最近 3 次采集的 v6 部分 ====="
tail -n 3 /www/lm/history.log | while read -r line; do
  echo "$line" | tr ' ' '\n' | grep '^v6-' | tr '\n' ' '
  echo
done

echo
echo "===== 各 v6 键最近 40 次的值分布 ====="
tail -n 40 /www/lm/history.log | tr ' ' '\n' | grep '^v6-' | sed 's/=.*//' | sort | uniq -c

echo
echo "===== 出口A v6 目标最近 40 次成功次数 ====="
for t in 阿里v6 腾讯v6 运营商v6; do
  ok=$(tail -n 40 /www/lm/history.log | tr ' ' '\n' | grep "^v6-pppoe-wan|$t=" | grep -vc FAIL)
  tot=$(tail -n 40 /www/lm/history.log | tr ' ' '\n' | grep -c "^v6-pppoe-wan|$t=")
  echo "  出口A $t : $ok / $tot 成功"
done

echo
echo "===== wan 侧 v6 目标最近 40 次 ====="
for t in 阿里v6 腾讯v6 运营商v6; do
  ok=$(tail -n 40 /www/lm/history.log | tr ' ' '\n' | grep "^v6-wan|$t=" | grep -vc FAIL)
  tot=$(tail -n 40 /www/lm/history.log | tr ' ' '\n' | grep -c "^v6-wan|$t=")
  echo "  wan $t : $ok / $tot 成功"
done

echo
echo "===== line_monitor.sh 里 v6 测试那几行 ====="
grep -n 'ping6\|ICMP6\|v6-' /usr/bin/line_monitor.sh | head -20
