echo "=== 默认路由 ==="
ip route show default
echo "=== mwan3 状态摘要 ==="
mwan3 status 2>/dev/null | head -20
echo "=== ping 223.5.5.5 (3 包) ==="
ping -c 3 -W 2 223.5.5.5 2>&1 | tail -4
echo "=== curl 阿里 DNS 解析测试 ==="
nslookup www.baidu.com 223.5.5.5 2>&1 | tail -5
echo "=== curl baidu 重试 ==="
curl -s -o /dev/null -w 'baidu http=%{http_code} time=%{time_total}\n' -m 12 https://www.baidu.com
echo "=== 飞书域名解析（指定 DNS）==="
nslookup open.feishu.cn 223.5.5.5 2>&1 | tail -6
echo "=== 飞书 webhook 重试 ==="
curl -s -m 20 -X POST -H 'Content-Type: application/json' -d '{"msg_type":"text","content":{"text":"【线路监测】飞书 webhook 连通性测试"}}' -w '\nhttp=%{http_code}\n' "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID"
echo
echo "=== /etc/resolv.conf ==="
cat /etc/resolv.conf