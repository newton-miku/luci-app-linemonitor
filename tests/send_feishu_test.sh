#!/bin/sh
# 走一遍 smstrun.py 的完整转发链路（不碰真实短信，直接喂一条仿真输出）。
# 在路由器上执行：sh /tmp/send_feishu_test.sh
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
print('转发标题:', m.read_title())

msg = '发件人:10086\n发件时间:26/10/02,10:30:00+32\n\n【链路自检】这是一条来自 smstrun.py 的仿真测试消息，用于确认飞书转发可用。'
if url:
    m.ensure_hosts_entry('open.feishu.cn')
    ok = m.push_feishu(msg, url, '【内置蜂窝】转发自检')
    print('飞书推送:', 'OK' if ok else 'FAILED')
else:
    print('未配置飞书，走 PPS+ 分支')
    tok = m.read_conf(m.TOKEN_CONF)
    if tok:
        print('PPS+ 推送:', 'OK' if m.push_pushplus(msg, tok, m.read_title()) else 'FAILED')
    else:
        print('两个后端都没配，forward() 会直接返回')
PY
