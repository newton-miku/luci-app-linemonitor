echo "=== 原始 resolv.conf ==="
cat /etc/resolv.conf
cp /etc/resolv.conf /tmp/resolv.conf.bak
echo
echo "=== 临时改成 127.0.0.1（本地 dnsmasq）==="
printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf
cat /etc/resolv.conf
echo "--- 解析测试 ---"
nslookup open.feishu.cn 2>&1 | tail -3
echo "--- curl 飞书 webhook ---"
curl -s -m 20 -X POST -H 'Content-Type: application/json' -d '{"msg_type":"text","content":{"text":"连通性测试 via 127.0.0.1 DNS"}}' -w '\nhttp=%{http_code}\n' "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID"
echo
echo "=== 组网客户端 的 DNS 接管设置 ==="
组网客户端 debug prefs 2>/dev/null | grep -i -E 'corpdns|acceptdns|dns' | head -10
echo
echo "=== 还原 ==="
cp /tmp/resolv.conf.bak /etc/resolv.conf
cat /etc/resolv.conf