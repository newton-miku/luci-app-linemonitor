#!/bin/sh
echo "=== 部署 ==="
sh /tmp/cld/deploy-cell/install.sh 2>&1

echo
echo "=== 新文件落盘确认 ==="
md5sum /usr/bin/smstrun.sh /usr/bin/smstrun.py
ls -l /usr/bin/smstrun.sh /usr/bin/smstrun.py

echo
echo "=== 观察 60 秒 ==="
i=0
while [ $i -lt 12 ]; do
    echo "t=+$((i*5))s py=$(ps w | grep -c '[s]mstrun.py') sh=$(ps w | grep -c '[s]mstrun.sh') pdu=$(ps w | grep -c '[p]du_decoder') seen=$(wc -l < /etc/smstrun-seen.conf)"
    sleep 5
    i=$((i+1))
done

echo
echo "=== 日志尾部 25 行 ==="
tail -n 25 /tmp/smstrun.log

echo
echo "=== 统计 ==="
echo "杀进程组提示: $(grep -c '已杀进程组' /tmp/smstrun.log) 次"
echo "返回码非零提示: $(grep -c '返回码' /tmp/smstrun.log) 次"
echo "未检测到新消息: $(grep -c '未检测到新消息' /tmp/smstrun.log) 次"
echo "Feishu response: $(grep -c 'Feishu response' /tmp/smstrun.log) 次"
echo "长短信分段未齐: $(grep -c '分段未齐' /tmp/smstrun.log) 次"
