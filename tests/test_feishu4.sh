echo "=== 1. HTTP（非 TLS）==="
curl -s -o /dev/null -w 'http://www.baidu.com http=%{http_code} t=%{time_total}\n' -m 12 http://www.baidu.com
echo "=== 2. HTTPS 详细（baidu）==="
curl -v -m 12 -o /dev/null https://www.baidu.com 2>&1 | grep -vE '^\s*[0-9]+\s+[0-9]+' | head -20
echo
echo "=== 3. HTTPS 用 IP 直连 ==="
curl -s -o /dev/null -w 'https://223.5.5.5 http=%{http_code} t=%{time_total}\n' -m 12 --insecure https://223.5.5.5
echo "=== 4. 飞书用 --resolve 绑 IP ==="
FWIP=$(nslookup open.feishu.cn 223.5.5.5 2>/dev/null | awk '/^Address [0-9]+:/{print $3; exit}')
echo "resolved FWIP=$FWIP"
curl -s -m 20 --resolve "open.feishu.cn:443:$FWIP" -X POST -H 'Content-Type: application/json' -d '{"msg_type":"text","content":{"text":"连通性测试 via --resolve"}}' -w '\nhttp=%{http_code}\n' "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID"
echo
echo "=== 5. /etc/resolv.conf 实际生效的 DNS 与 组网客户端 状态 ==="
组网客户端 status 2>&1 | head -5
echo "--- nslookup 用 100.100.100.100 ---"
nslookup open.feishu.cn 100.100.100.100 2>&1 | tail -4
echo "=== 6. dnsmasq 监听 ==="
netstat -lnup 2>/dev/null | grep -E ':53 '