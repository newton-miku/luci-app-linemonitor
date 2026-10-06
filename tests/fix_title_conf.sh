#!/bin/sh
# 清空 /usr/bin/smstrun-title.conf，让没带签名的短信彻底不设标题。
# 该文件原内容「未设置短信转发标题,新短信:」是 /usr/bin/dxzf.sh 选项 3 写进去的占位文案。
echo "=== 1) 清空前 ==="
if [ -f /usr/bin/smstrun-title.conf ]; then
    echo "字节数 = $(wc -c < /usr/bin/smstrun-title.conf)"
    cat /usr/bin/smstrun-title.conf
else
    echo "(文件不存在)"
fi

echo
echo "=== 2) 清空 ==="
cp /usr/bin/smstrun-title.conf /usr/bin/smstrun-title.conf.bak 2>/dev/null
echo "原内容已备份到 /usr/bin/smstrun-title.conf.bak（如需恢复原厂文案）"
: > /usr/bin/smstrun-title.conf
echo "清空后字节数 = $(wc -c < /usr/bin/smstrun-title.conf)"

echo
echo "=== 3) 验证 read_title() 与 sms_title() 的新行为 ==="
python3 -c "
import importlib.util
s = importlib.util.spec_from_file_location('m', '/usr/bin/smstrun.py')
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
print('read_title()          =', repr(m.read_title()))
print('sms_title(无签名正文)  =', repr(m.sms_title('HX-ECAp2f 拒收请回复R。')))
print('sms_title(带签名正文)  =', repr(m.sms_title('【腾讯科技】验证码 482913，5分钟内有效')))
print('sms_title(方括号签名)  =', repr(m.sms_title('[京东]您的订单已出库')))
"

echo
echo "=== 4) 转发进程状态 ==="
ps w | grep '[s]mstrun.py'
sleep 8
tail -n 4 /tmp/smstrun.log
