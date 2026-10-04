#!/bin/sh
# 短信飞书转发现状体检：进程 / conf / uci / 日志 / DNS
echo "=== 1) 进程 ==="
ps w | grep -E '[s]mstrun|[m]odeminit|[w]ebsocket_server'
echo
echo "=== 2) conf 文件 ==="
ls -l /usr/bin/smstrun-feishu.conf /usr/bin/smstrun.conf /usr/bin/smstrun-title.conf 2>&1
echo "--- feishu conf 长度与尾部 ---"
if [ -f /usr/bin/smstrun-feishu.conf ]; then
  wc -c < /usr/bin/smstrun-feishu.conf
  tail -c 16 /usr/bin/smstrun-feishu.conf
  echo
else
  echo "(不存在)"
fi
echo
echo "=== 3) uci modem 里的转发配置 ==="
uci show modem 2>/dev/null | grep -E 'feishu|wechat|notifications' 
echo
echo "=== 4) 运行期文件 ==="
ls -l /tmp/smstrun.log /tmp/smstrunsum.conf /tmp/smstrun.lock 2>&1
echo "--- /tmp/smstrun.log 尾部 40 行 ---"
tail -n 40 /tmp/smstrun.log 2>/dev/null || echo "(无日志)"
echo
echo "=== 5) DNS ==="
head -3 /etc/resolv.conf
echo "--- hosts 里的兜底条目 ---"
grep -n 'feishu' /etc/hosts 2>/dev/null || echo "(无)"
echo "--- 本地 dnsmasq 解析 ---"
nslookup open.feishu.cn 127.0.0.1 2>&1 | tail -6
echo
echo "=== 6) 短信脚本链路 ==="
ls -l /usr/bin/smstrun.sh /usr/bin/smstrun.py /usr/bin/pdu_decoder 2>&1
echo "--- /tmp/smstruns.at / smstrunt.at ---"
ls -l /tmp/smstruns.at /tmp/smstrunt.at 2>&1
echo
echo "=== 7) 开机自启里怎么起的 ==="
grep -n 'smstrun' /etc/init.d/modeminit 2>/dev/null
echo "--- /etc/rc.local ---"
cat /etc/rc.local 2>/dev/null | grep -v '^#' | grep -v '^$'
echo
echo "=== 8) 手工跑一次转发（看报错） ==="
cd /tmp && timeout 20 python3 /usr/bin/smstrun.py 2>&1 | head -20
echo "rc=$?"
