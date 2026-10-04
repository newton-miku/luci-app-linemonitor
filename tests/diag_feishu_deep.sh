#!/bin/sh
# 深挖：短信到底读不读得到
echo "=== 1) smstrun.sh 全文 ==="
cat /usr/bin/smstrun.sh
echo
echo "=== 2) sendat 在哪、能跑吗 ==="
which sendat
sendat 2>&1 | head -5
echo
echo "=== 3) 直接问模组：未读短信 AT+CMGL=0 ==="
echo "--- sendat 1 ---"
timeout 15 sendat 1 AT+CMGL=0 2>&1 | head -30
echo "rc=$?"
echo
echo "=== 4) 所有短信（含已读）AT+CMGL=4 ==="
timeout 15 sendat 1 AT+CMGL=4 2>&1 | head -40
echo
echo "=== 5) 模组信息 ==="
timeout 10 sendat 1 ATI 2>&1 | head -5
timeout 10 sendat 1 AT+CPMS? 2>&1 | head -5
echo
echo "=== 6) 手工跑 smstrun.sh 看输出 ==="
cd /tmp && timeout 25 sh /usr/bin/smstrun.sh 2>&1 | head -40
echo "rc=$?"
echo
echo "=== 7) 跑完后临时文件 ==="
ls -l /tmp/smstruns.at /tmp/smstrunt.at 2>&1
echo "--- smstrunt.at 内容 ---"
cat /tmp/smstrunt.at 2>/dev/null | head -20
echo
echo "=== 8) 汇总文件 ==="
cat /tmp/smstrunsum.conf 2>/dev/null
echo
echo "=== 9) 谁在占用 AT 通道 ==="
ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
ps w | grep -iE '[s]endat|[a]tcmd|[w]ebsocket|[m]odem' 
echo
echo "=== 10) 日志里出现过「发件人」吗 ==="
grep -c '发件人' /tmp/smstrun.log 2>/dev/null
echo "--- 日志里出现过的非「未检测到新消息」行 ---"
grep -v '未检测到新消息' /tmp/smstrun.log 2>/dev/null | tail -30
