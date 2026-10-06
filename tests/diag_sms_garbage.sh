#!/bin/sh
echo "=== 1. AT+CMGL=4 原始输出统计 ==="
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^' > /tmp/gl4.txt
echo "总行数: $(wc -l < /tmp/gl4.txt)"
echo "+CMGL 头条数: $(grep -c '^+CMGL:' /tmp/gl4.txt)"
echo
echo "--- 前 30 行 ---"
head -30 /tmp/gl4.txt

echo
echo "=== 2. seen 文件 ==="
echo "行数: $(wc -l < /etc/smstrun-seen.conf 2>/dev/null)"
echo "--- 头 15 行 ---"
head -15 /etc/smstrun-seen.conf 2>/dev/null
echo "--- 尾 15 行 ---"
tail -15 /etc/smstrun-seen.conf 2>/dev/null

echo
echo "=== 3. smstrun 日志尾部 ==="
tail -25 /tmp/smstrun.log 2>/dev/null

echo
echo "=== 4. 逐条解码，统计发件人合法性 ==="
awk '/^\+CMGL:/{idx=$2; getline pdu; print idx "\t" pdu}' /tmp/gl4.txt 2>/dev/null | head -40

echo
echo "=== 5. 短信存储占用 ==="
sendat 1 AT+CPMS? 2>/dev/null | tr -d '\r'
