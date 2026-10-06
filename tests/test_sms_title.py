# -*- coding: utf-8 -*-
"""短信标题提取的单元测试。

加载真机脚本（deploy-cell/usr/bin/smstrun.py）的前半段（到 forward() 之前），
这样不用在开发机上装 requests 也能测标题逻辑。

规则：正文里带【腾讯科技】这种签名就用它当标题，提不到再退回
/usr/bin/smstrun-title.conf 里配的固定标题，都没有就返回空串 —— 空标题时
飞书 post 不带 title 字段，卡片顶上不会多出一行没意义的占位文字。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'deploy-cell', 'usr', 'bin', 'smstrun.py')


def load_module():
    with open(SRC, encoding='utf-8') as f:
        src = f.read()
    head = src.split('def forward(')[0]
    head = head.replace('import requests\n', '')
    ns = {'__name__': 'smstrun_head'}
    exec(compile(head, SRC, 'exec'), ns)
    return ns


# (输入正文 / 已格式化的整条短信, 期望标题)
CASES = [
    ('【腾讯科技】您的验证码是 123456，5 分钟内有效。', '【腾讯科技】'),
    ('【中国移动】100MB流量日包已到账，即生效。', '【中国移动】'),
    ('[京东] 您的订单已发货。', '【京东】'),
    # 已格式化的整条短信：签名在正文段里，别被前面的元信息行带偏
    ('第40条短信\n发件人:106589666300\n发件时间:10/05/26 03:51:55\n'
     '（长短信 2 段已完整拼接）\n【中国联通】您的话费余额为 12.34 元。', '【中国联通】'),
    # 没有签名、也没有配固定标题 → 空串，代表这条不设标题
    ('HX/ECAp2f 拒收请回复R。', ''),
    ('', ''),
    # 括号里是空白 → 不当签名
    ('【  】测试', ''),
]


def main():
    ns = load_module()
    sms_title = ns['sms_title']

    fails = []
    for text, want in CASES:
        got = sms_title(text)
        if got != want:
            fails.append('sms_title(%r) = %r，期望 %r' % (text[:40], got, want))

    # 括号内容超过 20 字就不当签名（正常签名最长也就七八个字）
    long_sign = '【' + 'x' * 25 + '】正文'
    got = sms_title(long_sign)
    if got != '':
        fails.append('超长签名不应被当作标题，实际 %r' % got)

    if fails:
        for f in fails:
            print('FAIL ' + f)
        print('\n%d 项失败' % len(fails))
        return 1

    print('OK 标题提取 %d 例全部符合预期' % len(CASES))
    print('OK 超长签名被忽略')
    return 0


if __name__ == '__main__':
    sys.exit(main())
