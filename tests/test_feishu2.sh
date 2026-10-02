FW="https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID"
echo "=== DNS 解析 open.feishu.cn ==="
nslookup open.feishu.cn 2>&1 | tail -5
echo
echo "=== curl -v（看详细）==="
curl -v -m 15 -X POST -H 'Content-Type: application/json' -d '{"msg_type":"text","content":{"text":"连通性测试"}}' "$FW" 2>&1 | tail -30
echo "curl_exit=$?"
echo
echo "=== 对比：curl 百度 ==="
curl -s -o /dev/null -w 'baidu http=%{http_code} time=%{time_total}\n' -m 10 https://www.baidu.com
echo
echo "=== 用 python3 requests 试 ==="
python3 -c "
import requests, json
fw='https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK_ID'
try:
    r = requests.post(fw, json={'msg_type':'text','content':{'text':'连通性测试（python）'}}, timeout=15)
    print('status', r.status_code)
    print('body', r.text[:300])
except Exception as e:
    print('EXC', type(e).__name__, str(e)[:300])
"