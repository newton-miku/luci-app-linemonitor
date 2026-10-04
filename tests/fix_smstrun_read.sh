#!/bin/sh
echo "=== 1) 先看现在有没有卡死的 smstrun.sh / smstrun.py ==="
ps w | grep -E '[s]mstrun|[p]du_decoder'
echo
echo "=== 2) 杀掉可能卡住的进程 ==="
for p in $(ps w | grep -E '[s]mstrun\.sh|[p]du_decoder' | awk '{print $1}'); do
  echo "kill $p"
  kill -9 "$p" 2>/dev/null
done
sleep 1
ps w | grep -E '[s]mstrun' || echo "(smstrun.sh 已清)"
echo
echo "=== 3) 装新版 ==="
sh -n /tmp/new-smstrun.sh && echo "SHELL_SYNTAX_OK"
cp /tmp/new-smstrun.sh /usr/bin/smstrun.sh
chmod 755 /usr/bin/smstrun.sh
wc -c < /usr/bin/smstrun.sh
echo
echo "=== 4) 清基线，手工跑一次（记时） ==="
rm -f /etc/smstrun-seen.conf
s=$(date +%s)
cd /tmp && timeout 60 sh /usr/bin/smstrun.sh > /tmp/run1.txt 2>&1
rc=$?
e=$(date +%s)
echo "rc=$rc  耗时=$((e-s))s  输出字节=$(wc -c < /tmp/run1.txt)"
echo "--- 输出 ---"
cat /tmp/run1.txt
echo
echo "=== 5) seen 基线 ==="
wc -l < /etc/smstrun-seen.conf
cat /etc/smstrun-seen.conf
echo
echo "=== 6) 再跑一次（应为空 = 去重生效） ==="
s=$(date +%s)
cd /tmp && timeout 60 sh /usr/bin/smstrun.sh > /tmp/run2.txt 2>&1
rc=$?
e=$(date +%s)
echo "rc=$rc  耗时=$((e-s))s  输出字节=$(wc -c < /tmp/run2.txt)"
