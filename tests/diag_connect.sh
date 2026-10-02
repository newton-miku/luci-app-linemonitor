CT=4
EX_IF=eth1
echo "=== A: 带 Host 头（line_monitor 现在的写法）==="
for i in 1 2 3; do
  ms=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CT" -H "Host: weixin.qq.com" "http://117.89.182.41" 2>/dev/null)
  rc=$?
  echo "  rc=$rc raw=[$ms]"
done
echo "=== B: 不带 Host 头 ==="
for i in 1 2 3; do
  ms=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CT" "http://117.89.182.41" 2>/dev/null)
  rc=$?
  echo "  rc=$rc raw=[$ms]"
done
echo "=== C: 加 --no-keepalive 和不加 -o /dev/null ==="
for i in 1 2 3; do
  ms=$(curl --interface "$EX_IF" -s -o /dev/null -w '%{time_connect}|%{time_total}|%{http_code}|%{num_connects}' --connect-timeout "$CT" "http://117.89.182.41/" 2>/dev/null)
  rc=$?
  echo "  rc=$rc raw=[$ms]"
done
echo "=== D: 域名直连（走系统 DNS）==="
for i in 1 2 3; do
  ms=$(curl --interface "$EX_IF" -s -o /dev/null -w '%{time_connect}|%{time_namelookup}|%{num_connects}' --connect-timeout "$CT" "http://weixin.qq.com/" 2>/dev/null)
  rc=$?
  echo "  rc=$rc raw=[$ms]"
done
echo "=== curl 版本 ==="
curl --version | head -2