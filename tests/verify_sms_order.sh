#!/bin/sh
# 在路由器上离线验证新版 smstrun.sh：
# 用 SMSTRUN_RAW_FILE 注入真实 AT 输出，SMSTRUN_SEEN/OUT/TMP 全指向 /tmp，
# 完全不碰生产状态。重点验证「第一条 PDU 在第一个 +CMGL: 头之前」不再被丢弃。
D=/tmp/smsnew

echo "=== 0. 备份现有脚本 ==="
cp /usr/bin/smstrun.sh "$D/smstrun.sh.orig" 2>/dev/null && echo "已备份 smstrun.sh"
cp /usr/bin/smstrun.py "$D/smstrun.py.orig" 2>/dev/null && echo "已备份 smstrun.py"

echo
echo "=== 1. 抓一份原始 AT 输出作为测试输入 ==="
sendat 1 AT+CMGL=4 2>/dev/null > /tmp/sms_raw.txt
echo "raw 总行数: $(wc -l < /tmp/sms_raw.txt)"
echo "HEX 且长度>=20 的行数(理论应处理条数): $(tr -d '\r' < /tmp/sms_raw.txt | grep -c '^[0-9A-Fa-f]\{20,\}$')"
echo "CMGL 头数: $(tr -d '\r' < /tmp/sms_raw.txt | grep -c '^+CMGL:')"

echo
echo "=== 2. 新脚本语法检查 ==="
sh -n "$D/smstrun.sh" && echo "smstrun.sh 语法 OK"
python3 -m py_compile "$D/smstrun.py" && echo "smstrun.py 语法 OK"

echo
echo "=== 3. 离线跑新版（注入 raw，seen/out 全在 /tmp） ==="
rm -f /tmp/t.seen /tmp/t.out /tmp/t.at
SMSTRUN_RAW_FILE=/tmp/sms_raw.txt \
SMSTRUN_SEEN=/tmp/t.seen \
SMSTRUN_OUT=/tmp/t.out \
SMSTRUN_TMP=/tmp/t.at \
sh "$D/smstrun.sh" > /tmp/t.stdout 2>/tmp/t.stderr
echo "exit=$?  stdout=$(wc -c < /tmp/t.stdout)  stderr=$(wc -c < /tmp/t.stderr)"
echo "实际输出条数(第N条短信 标题): $(grep -c '^第.*条短信$' /tmp/t.out)"
echo "输出里的 发件人: 行数: $(grep -c '^发件人:' /tmp/t.out)"
echo "写入 seen 的行数: $(wc -l < /tmp/t.seen 2>/dev/null)"
echo "--- 前 3 条标题 ---"
grep '^第.*条短信$' /tmp/t.out | head -3
echo "--- 末 3 条标题 ---"
grep '^第.*条短信$' /tmp/t.out | tail -3
echo "--- 第一条的完整块（验证首条 PDU 是否被处理） ---"
sed -n '1,8p' /tmp/t.out
echo "--- stderr ---"
head -5 /tmp/t.stderr

echo
echo "=== 4. 对照：把 raw 里的首行 PDU 人为也放一份在头部后（模拟错位消解） ==="
echo "（跳过，见上一步条数即可判断）"

echo
echo "=== 5. 生产路径未受影响：不设 SMSTRUN_RAW_FILE 时仍走 sendat ==="
grep -c 'SMSTRUN_RAW_FILE' "$D/smstrun.sh"
