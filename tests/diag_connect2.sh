CT=4
EX_IF=eth1
zero=0; fail=0; ok=0; other=0
echo "--- 60 次带 Host 头测 117.89.182.41 ---"
for i in $(seq 1 60); do
  ms=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CT" -H "Host: weixin.qq.com" "http://117.89.182.41" 2>/dev/null)
  rc=$?
  case "$rc" in
    0|52|56)
      if [ "$ms" = "0.000000" ] || [ -z "$ms" ]; then zero=$((zero+1)); echo "  ZERO rc=$rc raw=[$ms]"; else ok=$((ok+1)); fi ;;
    *) fail=$((fail+1)) ;;
  esac
done
echo "ok=$ok zero=$zero fail=$fail"
echo "--- 同时看 num_connects / time_total 的对应关系（20 次）---"
for i in $(seq 1 20); do
  out=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}|%{time_total}|%{http_code}|%{num_connects}|%{size_download}' --connect-timeout "$CT" -H "Host: weixin.qq.com" "http://117.89.182.41" 2>/dev/null)
  rc=$?
  echo "  rc=$rc $out"
done