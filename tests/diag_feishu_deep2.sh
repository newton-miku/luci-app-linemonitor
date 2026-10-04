#!/bin/sh
# 探查 pdu_decoder 与 smstrun.sh 的接口细节
echo "=== pdu_decoder 是什么 ==="
file /usr/bin/pdu_decoder 2>/dev/null
head -c 64 /usr/bin/pdu_decoder | od -c | head -4
echo
echo "=== pdu_decoder 输出格式（拿第 4 步的一条真 PDU 试） ==="
cd /tmp && echo "0891683108801905F4640BA10156888806F10008620120014014232805000320020200480058002F004500430041007000320066002062D265368BF756DE590D00523002" | pdu_decoder 2>&1
echo
echo "=== 10658888601 那条（segment 2/2） ==="
cd /tmp && echo "0891683108801905F4640BA10156888806F10008620120014014232805000320020200480058002F004500430041007000320066002062D265368BF756DE590D00523002" > /tmp/x.at && cat /tmp/x.at | pdu_decoder 2>&1 | head -20
echo
echo "=== smstrun.sh 的字节（看有没有 CR） ==="
wc -c < /usr/bin/smstrun.sh
od -c /usr/bin/smstrun.sh | grep -c '\\r'
echo
echo "=== smstrun.py 里判定逻辑 ==="
grep -n '发件人\|subprocess\|read_token\|smstrun.sh\|sleep' /usr/bin/smstrun.py
echo
echo "=== 短信管理页面读过短信吗（LuCI 侧） ==="
ls -l /tmp/*.at /www/lm/*.sms 2>/dev/null
echo
echo "=== 模组的短信自动上报配置 ==="
cd /tmp && timeout 10 sendat 1 'AT+CNMI?' 2>&1 | head -5
timeout 10 sendat 1 'AT+CSMP?' 2>&1 | head -5
echo
echo "=== 模组主动上报（URC）串口被谁读 ==="
fuser -v /dev/ttyUSB0 /dev/ttyUSB1 2>&1 | head -10
cat /proc/$(pidof python3 | awk '{print $1}')/cmdline 2>/dev/null | tr '\0' ' '; echo
