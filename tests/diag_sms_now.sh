#!/bin/sh
echo "=== seen 里的垃圾键（完整） ==="
grep -v '^+*[0-9][0-9]*@' /etc/smstrun-seen.conf 2>/dev/null | head -20

echo
echo "=== seen 文件 mtime / 大小 ==="
ls -l /etc/smstrun-seen.conf
date

echo
echo "=== 当前 smstrun.sh 是否新版（应含 HEX 过滤） ==="
grep -c '0-9A-Fa-f' /usr/bin/smstrun.sh
md5sum /usr/bin/smstrun.sh
ls -l /usr/bin/smstrun.sh

echo
echo "=== AT+CMGL=4 原始输出的行统计 ==="
raw=$(sendat 1 AT+CMGL=4 2>/dev/null)
echo "总行数: $(printf '%s\n' "$raw" | wc -l)"
echo "CMGL 头数: $(printf '%s\n' "$raw" | grep -c '^+CMGL:')"
echo "纯十六进制且长度>=20 的行数: $(printf '%s\n' "$raw" | tr -d '\r' | grep -c '^[0-9A-Fa-f]\{20,\}$')"
echo "非空且非头且非HEX 的行数: $(printf '%s\n' "$raw" | tr -d '\r' | grep -v '^+CMGL:' | grep -v '^[0-9A-Fa-f]\{20,\}$' | grep -c .)"
echo

echo "=== 非HEX非头的行样本（最多 10 行） ==="
printf '%s\n' "$raw" | tr -d '\r' | grep -v '^+CMGL:' | grep -v '^[0-9A-Fa-f]\{20,\}$' | grep . | head -10

echo
echo "=== 手动跑一次 smstrun.sh，输出字节数 ==="
sh /usr/bin/smstrun.sh > /tmp/manual.out 2>/tmp/manual.err
echo "exit=$?  stdout=$(wc -c < /tmp/manual.out)  stderr=$(wc -c < /tmp/manual.err)"
head -30 /tmp/manual.out
echo "--- stderr ---"
head -5 /tmp/manual.err
