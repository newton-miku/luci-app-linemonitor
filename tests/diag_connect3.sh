CT=4
EX_IF=wan
echo "--- QQ (113.108.81.189) 带 Host 头 30 次，看 rc=52 时 -w 有没有输出 ---"
n52=0
for i in $(seq 1 30); do
  ms=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CT" -H "Host: qq.com" "http://113.108.81.189" 2>/dev/null)
  rc=$?
  case "$rc" in
    52|56) n52=$((n52+1)); echo "  rc=$rc raw=[$ms] len=${#ms}" ;;
  esac
done
echo "rc52/56 命中: $n52"
echo "--- 直接看 rc=52 时 curl 的完整 stderr/stdout ---"
ms=$(curl --interface "$EX_IF" -o /dev/null -s -w '%{time_connect}' --connect-timeout "$CT" -H "Host: qq.com" "http://113.108.81.189" 2>&1)
rc=$?
echo "rc=$rc out=[$ms]"
echo "--- 不带 -s（看它到底报什么） ---"
curl --interface "$EX_IF" -o /dev/null -w 'CONNECT=%{time_connect}\n' --connect-timeout "$CT" -H "Host: qq.com" "http://113.108.81.189" 2>&1 | tail -3
echo "rc=$?"