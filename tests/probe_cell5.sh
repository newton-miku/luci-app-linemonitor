echo "=== 所有 smstrun 相关文件 ==="
ls -la /usr/bin/ | grep -i smstrun
echo
echo "=== 所有 smstrun 配置文件内容 ==="
for f in /usr/bin/smstrun*.conf; do echo "--- $f ---"; cat "$f"; echo; done
echo
echo "=== smstrun-AK68.py 全文 ==="
cat /usr/bin/smstrun-AK68.py
echo
echo "=== 是否有非 AK68 版 smstrun.py ==="
ls -la /usr/bin/smstrun*.py 2>/dev/null