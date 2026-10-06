#!/bin/sh
echo "=== smstrun 进程 ==="
ps w | grep '[s]mstrun'

echo
echo "=== seen 行数 ==="
wc -l < /etc/smstrun-seen.conf

echo
echo "=== 触发用的目标键 ==="
grep -n '106589666300@10/05/26_03:51:55' /etc/smstrun-seen.conf || echo '(不在 seen 里)'

echo
echo "=== 日志尾部 ==="
tail -n 15 /tmp/smstrun.log

echo
echo "=== seen 里的垃圾键（非纯数字发件人） ==="
grep -cv '^+*[0-9]\{5,\}@' /etc/smstrun-seen.conf
