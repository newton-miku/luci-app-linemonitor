#!/bin/sh
# 1) 谁在显示短信（smsc.sh / rsmsc.sh）——重点看有没有分段合并
echo "=== smsc.sh ==="
cat /usr/share/modem/smsc.sh 2>/dev/null
echo
echo "=== rsmsc.sh ==="
cat /usr/share/modem/rsmsc.sh 2>/dev/null
echo
echo "=== 其他 modem 脚本 ==="
ls /usr/share/modem/ 2>/dev/null
echo
# 2) pdu_decoder 是什么
echo "=== pdu_decoder ==="
ls -l /usr/bin/pdu_decoder 2>/dev/null
head -c 60 /usr/bin/pdu_decoder 2>/dev/null | tr -d '\0'
echo
# 喂一行假数据进去，看它输出什么格式（务必有换行，否则会挂）
echo "=== pdu_decoder 试跑 ==="
printf 'AT+CMGL=4\n\n' | timeout 5 pdu_decoder 2>&1 | head -20
echo "rc=$?"
