#!/bin/sh
# 在真机上验证「短信标题」这条链路：签名提取 + 固定标题兜底。
# 不依赖 requests，也不发任何网络请求。
python3 - <<'PYEOF'
import importlib.util
spec = importlib.util.spec_from_file_location("sm", "/usr/bin/smstrun.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

fallback = m.read_title()
print("smstrun-title.conf 里的固定标题 = %r" % fallback)

cases = [
    ("【腾讯科技】您的验证码是 123456。", "【腾讯科技】"),
    ("【中国移动】100MB流量日包已到账。", "【中国移动】"),
    ("[京东] 您的订单已发货。", "【京东】"),
    ("第40条短信\n发件人:106589666300\n发件时间:10/05/26 03:51:55\n"
     "（长短信 2 段已完整拼接）\n【中国联通】余额 12.34 元。", "【中国联通】"),
    ("HX/ECAp2f 拒收请回复R。", fallback),
    ("", fallback),
    ("【  】测试", fallback),
]

bad = 0
for text, want in cases:
    got = m.sms_title(text)
    if got != want:
        bad += 1
        print("FAIL sms_title(%r) = %r（期望 %r）" % (text[:24], got, want))
    else:
        print("OK   sms_title(%r) = %r" % (text[:24], got))

long_sign = "【" + "x" * 25 + "】正文"
if m.sms_title(long_sign) != fallback:
    bad += 1
    print("FAIL 超长签名未被忽略: %r" % m.sms_title(long_sign))
else:
    print("OK   超长签名被忽略")

print("---")
print("失败 %d 项" % bad)
PYEOF
