#!/bin/sh
echo "=== A) 输出到底长什么样（存文件后逐行编号打印）==="
sh /usr/bin/smstrun.sh > /tmp/raw.out 2>/tmp/raw.err
echo "rc=$?  stdout=$(wc -c < /tmp/raw.out)  stderr=$(wc -c < /tmp/raw.err)"
echo "--- stdout 前 60 行（每行前 200 字符）---"
head -c 4000 /tmp/raw.out | sed -n '1,60p' | cut -c1-200
echo "--- 尾部 20 行 ---"
tail -n 20 /tmp/raw.out | cut -c1-200
echo
echo "=== B) stdout 里含不含「发件人」 ==="
grep -c '发件人' /tmp/raw.out
echo "=== C) 块标题行 ==="
grep -c '^第.*条短信' /tmp/raw.out
echo "=== D) 分段信息 ==="
grep -E 'Reference number|SMS segment' /tmp/raw.out | head -n 20
echo
echo "=== E) 有没有卡住的进程 ==="
ps w | grep -E '[s]mstrun|[p]du_decoder|[s]endat'
echo
echo "=== F) stderr ==="
head -n 20 /tmp/raw.err
