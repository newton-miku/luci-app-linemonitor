#!/bin/sh
echo "=== seen 全部内容 ==="
cat -n /etc/smstrun-seen.conf

echo
echo "=== 进程采样 5 次（每次间隔 3 秒） ==="
i=0
while [ $i -lt 5 ]; do
    echo "--- 采样 $i ---"
    ps w | grep 'smstrun' | grep -v 'grep'
    sleep 3
    i=$((i + 1))
done

echo
echo "=== 调用方排查 ==="
echo "--- crontab ---"
crontab -l 2>/dev/null | grep -i sms || echo "(无)"
echo "--- /etc/init.d/modeminit 里的 smstrun ---"
grep -n 'smstrun' /etc/init.d/modeminit || echo "(无)"
echo "--- /etc/crontabs/ ---"
ls -l /etc/crontabs/ 2>/dev/null
grep -rn 'smstrun' /etc/crontabs/ 2>/dev/null || echo "(无)"
echo "--- 引用 smstrun.sh 的文件 ---"
grep -rln 'smstrun\.sh' /usr/bin /etc/init.d /etc/hotplug.d /etc/rc.d 2>/dev/null

echo
echo "=== smstrun-restart.sh ==="
cat /usr/bin/smstrun-restart.sh 2>/dev/null
