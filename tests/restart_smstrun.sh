#!/bin/sh
echo "=== 1) 重启 smstrun.py 让新读取逻辑生效 ==="
for p in $(ps w | grep '[s]mstrun\.py' | awk '{print $1}'); do
  echo "kill smstrun.py pid=$p"
  kill "$p" 2>/dev/null
done
for p in $(ps w | grep -E '[s]mstrun\.sh|[p]du_decoder' | awk '{print $1}'); do
  kill -9 "$p" 2>/dev/null
done
sleep 2
rm -f /tmp/smstrun.lock
echo
echo "=== 2) 清基线，让首次启动把存量短信推一遍 ==="
rm -f /etc/smstrun-seen.conf
echo
echo "=== 3) 启动 ==="
nohup python3 /usr/bin/smstrun.py > /tmp/smstrun.log 2>&1 &
sleep 12
echo "--- 进程 ---"
ps w | grep -E '[s]mstrun'
echo
echo "=== 4) 日志 ==="
cat /tmp/smstrun.log
echo
echo "=== 5) 汇总文件（推送内容的快照） ==="
cat /tmp/smstrunsum.conf 2>/dev/null
echo
echo "=== 6) 基线 ==="
wc -l < /etc/smstrun-seen.conf 2>/dev/null
echo
echo "=== 7) 再等 12 秒，确认没有重复推送 ==="
wc -c < /tmp/smstrunsum.conf
sleep 12
wc -c < /tmp/smstrunsum.conf
echo "行数变化即可判断有没有重复推："
wc -l < /tmp/smstrunsum.conf
