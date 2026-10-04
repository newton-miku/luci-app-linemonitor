#!/bin/sh
echo "=== 1) 等两轮采集，确认没卡死 ==="
sleep 20
ps w | grep -E '[s]mstrun'
echo
echo "=== 2) 日志（看飞书推送与攒段行为）==="
cat /tmp/smstrun.log
echo
echo "=== 3) 本次新增的转发记录（按 mtime 找最后一段）==="
tail -c 3000 /tmp/smstrunsum.conf
echo
echo "=== 4) pending 缓冲（长短信攒段状态）==="
grep -c '本' /tmp/smstrunsum.conf 2>/dev/null
echo
echo "=== 5) hosts 兜底行 ==="
grep smstrun /etc/hosts
