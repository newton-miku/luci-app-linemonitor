#!/bin/sh
echo "=== 1) 找内置蜂窝 web 页里可能做分段合并的代码 ==="
for f in /usr/lib/lua/luci/view/zmode/*.htm /usr/lib/lua/luci/view/zmode/*.lua /usr/lib/lua/luci/model/cbi/modem.lua /usr/lib/lua/luci/model/cbi/modem5700-AK68.lua; do
  [ -f "$f" ] || continue
  hit=$(grep -c -E 'segment|concat|concatAll|merge|Reference number' "$f" 2>/dev/null)
  [ "$hit" != "0" ] && echo "$hit  $f"
done
echo
echo "=== 2) pdu_decoder 自己会不会合并 ==="
which pdu_decoder
pdu_decoder 2>&1 | head -20
echo
echo "=== 3) pdu_decoder 源/脚本 ==="
ls -l /usr/bin/pdu_decoder 2>/dev/null
file /usr/bin/pdu_decoder 2>/dev/null || head -c 200 /usr/bin/pdu_decoder 2>/dev/null | od -c | head -5
echo
echo "=== 4) 原厂 smstrun.sh 备份（看有没有分段处理） ==="
ls -l /root/cell-sms-backup/ 2>/dev/null
echo
echo "=== 5) 谁在显示已读短信（smsc.sh / rsmsc.sh）==="
ls -l /usr/share/modem/ 2>/dev/null
echo "--- smsc.sh ---"
cat /usr/share/modem/smsc.sh 2>/dev/null | head -60
echo
echo "--- rsmsc.sh ---"
cat /usr/share/modem/rsmsc.sh 2>/dev/null | head -60
