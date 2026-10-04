#!/bin/sh
echo "=== 1) 装新版 smstrun.sh ==="
cp /tmp/new-smstrun.sh /usr/bin/smstrun.sh
chmod +x /usr/bin/smstrun.sh
sh -n /usr/bin/smstrun.sh && echo "SHELL_SYNTAX_OK"

echo
echo "=== 2) 清空 seen（换指纹格式，必须重来）==="
rm -f /etc/smstrun-seen.conf
: > /etc/smstrun-seen.conf
echo "已清空"

echo
echo "=== 3) 跑一次 smstrun.sh，看 4 段是不是都出来了 ==="
sh /usr/bin/smstrun.sh > /tmp/raw3.out 2>/tmp/raw3.err
echo "stdout 字节 = $(wc -c < /tmp/raw3.out)"
grep -c '^第' /tmp/raw3.out
echo "--- 各块 ---"
awk '/^第/{h=$0} /^SMS segment/{print h"  "$0}' /tmp/raw3.out | head -n 20
echo
echo "--- seen 记录（应为 4 行，段号 1,2,3,4）---"
cat /etc/smstrun-seen.conf

echo
echo "=== 4) 再跑一次：应输出 0 字节（全部段都已记过）==="
sh /usr/bin/smstrun.sh 2>/dev/null | wc -c

echo
echo "=== 5) 喂给 merge_sms，看是否拼成完整 4 段 ==="
python3 - <<'PYEOF'
import importlib.util
spec = importlib.util.spec_from_file_location("sm", "/usr/bin/smstrun.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
raw = open("/tmp/raw3.out", encoding="utf-8", errors="replace").read()
print("输入块数 =", len(m.parse_blocks(raw)))
out = m.merge_sms(raw)
print("merge 输出长度 =", len(out))
print(out)
print("=" * 60)
print("含『发件人』 =", "发件人" in out)
PYEOF
