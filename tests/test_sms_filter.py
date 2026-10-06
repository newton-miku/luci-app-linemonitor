# -*- coding: utf-8 -*-
"""垃圾短信过滤的单元测试。

加载真机脚本（deploy-cell/usr/bin/smstrun.py）的前半段（到 forward() 之前），
这样不用在开发机上装 requests 也能测过滤逻辑。

数据取自 2026-10-05 实机 `/etc/smstrun-seen.conf` 里那批乱码键 —— 模组 ME 中
40 个坏槽位被 AT+CMGL=4 列出来，pdu_decoder 解出的发件人 / 时间 / 段数全都不合法。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'deploy-cell', 'usr', 'bin', 'smstrun.py')

GARBAGE_SENDERS = [
    '?7000000100000000',
    '?70000001000000000000000000',
    '6=88<4>4:3757435?>08=?=698:5<<;88<',
    '<>67>705=025::25;',
    '=265=?97;?258:00',
    '328850003099302009:15',
    '32885000303=303035375',
    '?70000001000000000000000000>5258?70',
    '?700000010000000000000',
    '?7000000100000000000000',
    '41?',
    '306',                      # 纯数字但太短，真短号最短 5 位
    '0020601241>>7<76',
    '',                         # 空发件人
]

GOOD_SENDERS = ['10658888601', '106589666300', '10086', '1065896652061002',
                '+8613800138000', '95588']

GARBAGE_TIMES = [
    '05/31/92 08:00:00',        # 1992
    '12/06/99 16:20:37',        # 1999
    '12/29/97 08:23:00',        # 1997
    '08/03/64 06:41:15',        # 1964
    '07/31/04 09:33:32',        # 2004
    '11/30/56 08:02:33',        # 1956
    '12/09/15 08:03:00',        # 2015，早于 2018
    '10/05/13 21:00:00',        # 2013
    '04/05/92 08:00:00',
    # 注意 '02/07/19 21:00:00'（2019）不在这个列表里：年份本身落在 18~35
    # 区间内，按设计就该放行，它对应的垃圾记录靠发件人 `?7000` 那关拦住。
    '',
]

GOOD_TIMES = ['10/02/26 18:04:41', '10/05/26 03:51:55', '10/04/26 17:05:27']


def load_module():
    with open(SRC, encoding='utf-8') as f:
        src = f.read()
    head = src.split('def forward(')[0]
    head = head.replace('import requests\n', '')
    ns = {'__name__': 'smstrun_head'}
    exec(compile(head, SRC, 'exec'), ns)
    return ns


def main():
    ns = load_module()
    valid_sender = ns['valid_sender']
    valid_time = ns['valid_time']
    parse_blocks = ns['parse_blocks']

    fails = []

    for s in GARBAGE_SENDERS:
        if valid_sender(s):
            fails.append('垃圾发件人未被拦住: %r' % s)
    for s in GOOD_SENDERS:
        if not valid_sender(s):
            fails.append('真号码被误杀: %r' % s)

    for t in GARBAGE_TIMES:
        if valid_time(t):
            fails.append('垃圾时间未被拦住: %r' % t)
    for t in GOOD_TIMES:
        if not valid_time(t):
            fails.append('真时间被误杀: %r' % t)

    # 整条短消息：垃圾块应被 parse_blocks 丢掉，正常块留下
    sample = '\n'.join([
        '第20条短信',
        '发件人:328850003099302009:15',
        '发件时间:12/09/15 08:03:00',
        '',
        '正文A',
        '------------------------------------------------------',
        '第12条短信',
        '发件人:6=88<4>4:3757435?>08=?=698:5<<;88<',
        '发件时间:07/31/04 09:33:32',
        'Reference number: 9',
        'SMS segment 1 of 17',
        '正文B',
        '------------------------------------------------------',
        '第39条短信',
        '发件人:?7000000100000000000000',
        '发件时间:04/05/92 08:00:00',
        'SMS segment 1 of 96',
        '正文C',
        '------------------------------------------------------',
        '第40条短信',
        '发件人:106589666300',
        '发件时间:10/05/26 03:51:55',
        'Reference number: 14',
        'SMS segment 1 of 2',
        '真短信正文',
        '------------------------------------------------------',
        '第41条短信',
        '发件人:106589666300',
        '发件时间:10/05/26 04:00:34',
        'SMS segment 1 of 188',
        '段数荒谬',
        '------------------------------------------------------',
    ])
    blocks = parse_blocks(sample)
    if len(blocks) != 1:
        fails.append('parse_blocks 应只留下 1 条，实际 %d 条: %r'
                     % (len(blocks), [b.get('from') for b in blocks]))
    elif blocks[0]['from'] != '106589666300':
        fails.append('留下的不是真短信: %r' % blocks[0]['from'])

    if fails:
        for f in fails:
            print('FAIL ' + f)
        print('\n%d 项失败' % len(fails))
        return 1

    print('OK 垃圾发件人 %d 例全拦住 / 真号码 %d 例全通过'
          % (len(GARBAGE_SENDERS), len(GOOD_SENDERS)))
    print('OK 垃圾时间 %d 例全拦住 / 真时间 %d 例全通过'
          % (len(GARBAGE_TIMES), len(GOOD_TIMES)))
    print('OK parse_blocks 从 5 条混合块里只留下 1 条真短信')
    return 0


if __name__ == '__main__':
    sys.exit(main())
