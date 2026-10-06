#!/bin/sh
echo "=== timeout applet 是否存在 ==="
if command -v timeout >/dev/null 2>&1; then
    echo "有 timeout: $(command -v timeout)"
    timeout 2 sleep 10
    echo "timeout 2 sleep 10 -> rc=$? (124=正常超时, 0=没超时)"
else
    echo "没有 timeout"
fi

echo
echo "=== 单轮 smstrun.sh 耗时 ==="
t0=$(date +%s)
sh /usr/bin/smstrun.sh > /dev/null 2>&1
echo "rc=$?"
t1=$(date +%s)
echo "耗时 $((t1 - t0)) 秒"

echo
echo "=== 连续观察 30 秒内的进程数 ==="
i=0
while [ $i -lt 6 ]; do
    n_sh=$(ps w | grep -c '[s]mstrun.sh')
    n_py=$(ps w | grep -c '[s]mstrun.py')
    n_pd=$(ps w | grep -c '[p]du_decoder')
    n_sa=$(ps w | grep -c '[s]endat')
    echo "t=+$((i*5))s  sh=$n_sh py=$n_py pdu_decoder=$n_pd sendat=$n_sa"
    sleep 5
    i=$((i + 1))
done
