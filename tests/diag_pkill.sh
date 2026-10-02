echo "=== pkill -f 是否工作 ==="
pkill -f 'python3 /usr/bin/smstrun.py'; echo "pkill rc=$?"
sleep 2
ps w | grep '[s]mstrun.py' || echo "(全杀掉了)"
echo
echo "=== busysbox 版本与 pkill 支持 ==="
busybox 2>&1 | head -2
which pkill; ls -l $(which pkill)
echo
echo "=== uci show modem 全量（前 40 行）==="
uci show modem | head -40
echo
echo "=== modem 配置文件名 ==="
ls -l /etc/config/modem
echo
echo "=== 配置里 feishu/wechat 出现次数 ==="
grep -c 'feishu\|wechat' /etc/config/modem || echo 0