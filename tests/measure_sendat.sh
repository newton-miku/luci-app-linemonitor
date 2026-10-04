#!/bin/sh
echo "=== sendat 两种查询的耗时（带 timeout 计时） ==="
echo "--- AT+CMGL=0 ---"
s=$(date +%s)
timeout 30 sendat 1 AT+CMGL=0 > /tmp/q0.txt 2>&1
rc=$?
e=$(date +%s)
echo "rc=$rc 耗时=$((e-s))s 字节=$(wc -c < /tmp/q0.txt)"
echo
echo "--- AT+CMGL=4 ---"
s=$(date +%s)
timeout 30 sendat 1 AT+CMGL=4 > /tmp/q4.txt 2>&1
rc=$?
e=$(date +%s)
echo "rc=$rc 耗时=$((e-s))s 字节=$(wc -c < /tmp/q4.txt)"
echo
echo "=== pdu_decoder 单次耗时 ==="
pdu=$(grep -A2 '^+CMGL: 0,' /tmp/q4.txt | sed -n '3p' | tr -d '\r')
echo "PDU=$pdu"
s=$(date +%s%N 2>/dev/null || date +%s)
printf '%s' "$pdu" | timeout 20 pdu_decoder > /tmp/pd.txt 2>&1
rc=$?
e=$(date +%s%N 2>/dev/null || date +%s)
echo "rc=$rc"
cat /tmp/pd.txt
