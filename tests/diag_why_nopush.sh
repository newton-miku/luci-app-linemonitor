#!/bin/sh
echo "=== 1) 日志里跟这两个可疑发件人相关的行 ==="
grep -n '106589666300\|11/30/99\|长短信\|StatusCode\|Feishu' /tmp/smstrun.log | tail -n 30
echo
echo "=== 2) 汇总文件里有没有 10/05 或 11/30 的内容 ==="
grep -n '10/05/26\|11/30/99' /tmp/smstrunsum.conf | head
echo
echo "=== 3) 这两条可疑指纹是谁加的：先摘掉，重跑一次看它还吐不吐 ==="
echo "--- 摘除前 seen ---"
cat /etc/smstrun-seen.conf
grep -v '10/05/2603:51:55\|11/30/9923:24:30' /etc/smstrun-seen.conf > /tmp/seen.new
cp /tmp/seen.new /etc/smstrun-seen.conf
echo "--- 摘除后行数 ---"
wc -l < /etc/smstrun-seen.conf
echo
echo "--- 重跑 smstrun.sh，这次应该吐内容 ---"
sh /usr/bin/smstrun.sh > /tmp/raw2.out 2>/tmp/raw2.err
echo "stdout 字节 = $(wc -c < /tmp/raw2.out)"
cat /tmp/raw2.out | cut -c1-170
echo
echo "--- stderr ---"
head -n 10 /tmp/raw2.err
echo
echo "=== 4) 把这段喂给 merge_sms，看它怎么处理 ==="
python3 - <<'PYEOF'
import importlib.util
spec = importlib.util.spec_from_file_location("sm", "/usr/bin/smstrun.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
raw = open("/tmp/raw2.out", encoding="utf-8", errors="replace").read()
print("输入块数 =", len(m.parse_blocks(raw)))
for b in m.parse_blocks(raw):
    print("  idx=%s from=%r time=%r ref=%s seg=%s/%s body=%r"
          % (b.get("idx"), b.get("from"), b.get("time"), b.get("ref"),
             b.get("seg"), b.get("segs"), "".join(b["body"])[:40]))
msgs = m.merge_sms(raw)
print("merge 结果条数 =", len(msgs))
for one in msgs:
    print("标题 =", repr(m.sms_title(one)))
    print(one[:600])
PYEOF
