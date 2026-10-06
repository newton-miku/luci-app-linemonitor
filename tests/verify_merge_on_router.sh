#!/bin/sh
# 在真机上用合成数据验证「跨轮次攒段 + 拼接」这条核心路径
cat > /tmp/tm.py <<'PYEOF'
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("sm", "/usr/bin/smstrun.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("python:", sys.version.split()[0])

def blk(idx, frm, tm, ref, seg, segs, body):
    s = "第%s条短信\n发件人:%s\n发件时间:%s\n" % (idx, frm, tm)
    if ref is not None:
        s += "Reference number: %s\nSMS segment %d of %d\n" % (ref, seg, segs)
    s += body + "\n" + "-" * 54 + "\n"
    return s

def feed(txt, tag):
    r = m.merge_sms(txt)
    print("[%s] 推送条数=%d" % (tag, len(r)))
    for one in r:
        print("标题 = %r" % m.sms_title(one))
        print(one)
    print("-" * 60)
    return r

F = "106589666300"
T = "10/03/26 17:31:56"

print("### 轮1：3 段短信只到 1、3 段（缺中段）→ 应不推")
feed(blk("4", F, T, "163", 1, 3, "【中国移动】100MB流量日包已到账，")
     + blk("6", F, T, "163", 3, 3, "即生效，24小时后自动失效。"), "轮1")

print("### 轮2：补上第 2 段 → 应立即拼成一条完整消息推送")
feed(blk("5", F, T, "163", 2, 3, "MB（编号：25JT206613），资费0元，"), "轮2")

print("### 轮3：普通单段短信 → 应照常推送")
feed(blk("7", "10658888601", "10/04/26 17:05:27", None, 0, 0, "HX/ECAp2f 拒收请回复R。"), "轮3")

print("### 轮4：空输入 → 返回空列表")
feed("", "轮4")

print("### 轮5：超时兜底（把 at 改成很久以前）")
k = list(m._pending.keys())[0] if m._pending else None
print("pending 残留:", list(m._pending.keys()))
PYEOF
python3 /tmp/tm.py
