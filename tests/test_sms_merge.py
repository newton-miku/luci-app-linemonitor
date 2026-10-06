import importlib.util

spec = importlib.util.spec_from_file_location('smstrun_mod', '/usr/bin/smstrun.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def block(idx, frm, tm, ref, seg, segs, body):
    s = '第%s条短信\n发件人:%s\n发件时间:%s\n' % (idx, frm, tm)
    if ref is not None:
        s += 'Reference number: %s\n' % ref
    if seg is not None:
        s += 'SMS segment %d of %d\n' % (seg, segs)
    s += body
    s += '\n' + '-' * 54 + '\n'
    return s


# 场景一：3 段短信，第 1 轮只到第 2、3 段（第一段已被模组清掉），应先攒着不推
r1 = (block(4, '106589666300', '10/03/26 17:31:56', 163, 2, 3, 'MB（编号：25JT206613），资费0元')
      + block(6, '106589666300', '10/03/26 17:31:57', 163, 3, 3, '即生效，24小时后自动失效。'))
print('=== 轮 1（3 段只到 2 段，应先攒着不推）===')
m1 = mod.merge_sms(r1)
print('输出条数 =', len(m1))
print('pending 组数 =', len(mod._pending))

# 场景二：同一 ref 的 3 段分两轮到齐，第 2 轮应拼成完整一条
r2 = block(8, '106589666300', '10/03/26 17:31:55', 163, 1, 3, '【中国移动】100MB流量日包已到账，')
print()
print('=== 轮 2（第 1 段补齐，应立即完整推出）===')
m2 = mod.merge_sms(r2)
print('\n'.join(m2))
print('输出条数 =', len(m2))
print('标题 =', mod.sms_title(m2[0]) if m2 else '(无)')
print('pending 组数 =', len(mod._pending))

# 场景三：普通单条短信，正文里没有签名 → 标题应为空串
r3 = block(0, '10658888601', '10/02/26 18:04:41', 32, None, None, 'HX/ECAp2f 拒收请回复R。')
print()
print('=== 轮 3（普通短信，无签名 → 不设标题）===')
m3 = mod.merge_sms(r3)
print('\n'.join(m3))
print('输出条数 =', len(m3))
print('标题 =', repr(mod.sms_title(m3[0])) if m3 else '(无)')

# 场景四：空输入
print()
print('=== 轮 4（空输入）===')
print('返回 =', repr(mod.merge_sms('')))

# 场景五：超时兜底 —— 把 pending 的时间戳改成很久以前
mod._pending[('x', 'y')] = {'segs': 3, 'parts': {1: 'a', 2: 'b'}, 'idx': '9',
                            'time': '10/04/26 17:00:00', 'at': mod.time.time() - 3600}
print()
print('=== 轮 5（超时兜底，只到 2/3 段也推）===')
m5 = mod.merge_sms(block(11, 'x', '10/04/26 17:00:00', 'y', 1, 3, 'a'))
print('\n'.join(m5))
print('输出条数 =', len(m5))
