#!/bin/sh
# 先把 Python 停掉，排除并发互相覆盖 /tmp/smstrunt.at 的干扰
echo "=== 0) 停掉转发进程（诊断期间）==="
for p in $(ps w | grep '[s]mstrun\.py' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
for p in $(ps w | grep -E '[s]mstrun\.sh|[p]du_decoder' | awk '{print $1}'); do kill -9 "$p" 2>/dev/null; done
sleep 2
ps w | grep -E '[s]mstrun|[p]du_decoder' || echo "已全部停止"

echo
echo "=== 1) 原始 AT 应答统计 ==="
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -c '^+CMGL:'
echo "非空数据行（+CMGL 之后、OK 之前的行）:"
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -vE '^\^|^OK|^\+CMGL:|^\+CMS ERROR|^$' | wc -c

echo
echo "=== 2) 单独跑 pdu_decoder 看输出 ==="
n=0
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^' | while IFS= read -r line; do
  case "$line" in +CMGL:*) continue;; esac
  [ -n "$line" ] || continue
  n=$((n+1))
  if [ "$n" -le 3 ]; then
    echo "--- 第 $n 条 PDU（长度 ${#line}）---"
    echo "$line" | pdu_decoder 2>&1 | cut -c1-160
  fi
done

echo
echo "=== 3) 跑 smstrun.sh，分别看中间文件 ==="
rm -f /tmp/smstruns.at /tmp/smstrunt.at /tmp/raw.out
sh /usr/bin/smstrun.sh > /tmp/raw.out 2>/tmp/raw.err
echo "rc=$?"
echo "smstrunt.at (TMP) 字节 = $(wc -c < /tmp/smstruns.at 2>/dev/null)"
echo "smstrunt.at (OUT) 字节 = $(wc -c < /tmp/smstrunt.at 2>/dev/null)"
echo "stdout 字节 = $(wc -c < /tmp/raw.out)"
echo
echo "--- TMP 内容（前 20 行）---"
head -n 20 /tmp/smstruns.at 2>/dev/null | cut -c1-160
echo
echo "--- OUT 内容（前 20 行）---"
head -n 20 /tmp/smstrunt.at 2>/dev/null | cut -c1-160
echo
echo "=== 4) 单独测 sed 一步 ==="
sed -e '/^Textlen=/d' -e 's/^From:/发件人:/' -e 's/^Date\/Time:/发件时间:/' /tmp/smstruns.at > /tmp/sed.out 2>/tmp/sed.err
echo "sed rc=$?  输出字节=$(wc -c < /tmp/sed.out)"
cat /tmp/sed.err
echo
echo "=== 5) seen 行数 ==="
wc -l < /etc/smstrun-seen.conf
