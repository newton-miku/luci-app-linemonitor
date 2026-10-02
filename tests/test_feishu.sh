echo "=== hosts 现状 ==="
grep -n 'smstrun-feishu' /etc/hosts || echo "(无)"
echo
echo "=== 清掉旧条目后做一次真实推送 ==="
sed -i '/smstrun-feishu/d' /etc/hosts
cd /usr/bin && python3 -c "
import smstrun, time
url = smstrun.read_conf(smstrun.FEISHU_CONF)
print('url:', url)
print('ensure:', smstrun.ensure_hosts_entry('open.feishu.cn'))
t0 = time.time()
smstrun.push_feishu('【测试】路由器内置蜂窝短信转发已切到飞书。\n收到这条说明 webhook 通了。', url, '线路监测·短信转发测试')
print('耗时: %.2fs' % (time.time() - t0))
"
echo
echo "=== 推送后 hosts ==="
grep -n 'smstrun-feishu' /etc/hosts || echo "(无)"