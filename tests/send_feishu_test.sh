#!/bin/sh
# 走一遍 smstrun.py 的完整转发链路（不碰真实短信，直接喂一条仿真输出）。
# 在路由器上执行：sh /tmp/send_feishu_test.sh
#
# 顺便验证新的标题逻辑：正文里带【腾讯科技】这种签名时，飞书卡片的标题
# 直接用签名本身，不再用 smstrun-title.conf 里那句固定文案。
cd /usr/bin || exit 1
python3 - <<'PY'
import sys
sys.path.insert(0, '/usr/bin')
import importlib.util

spec = importlib.util.spec_from_file_location('smstrun', '/usr/bin/smstrun.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

url = m.read_conf(m.FEISHU_CONF)
print('飞书配置:', (url[:48] + '…') if url else '(空)')
print('PPS+ token:', '(已配置)' if m.read_conf(m.TOKEN_CONF) else '(未配置)')
print('固定标题配置:', repr(m.read_title()))

msg = ('发件人:10693041407221460\n'
       '发件时间:10/06/26 11:20:00\n'
       '【腾讯科技】您的验证码是 482913，5 分钟内有效。')
title = m.sms_title(msg)
print('---')
print('挑出的标题:', repr(title))
if url:
    m.ensure_hosts_entry('open.feishu.cn')
    print('飞书推送:', 'OK' if m.push_feishu(msg, url, title) else 'FAILED')
else:
    tok = m.read_conf(m.TOKEN_CONF)
    print('未配置飞书，走 PPS+ 分支:', '已配置' if tok else '未配置')
    if tok:
        print('PPS+ 推送:', 'OK' if m.push_pushplus(msg, tok, title) else 'FAILED')
PY
