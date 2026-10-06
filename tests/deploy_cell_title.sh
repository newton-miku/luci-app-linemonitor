#!/bin/sh
# 部署 deploy-cell（先 scp /tmp/celldeploy.tar 上来），并验证短信标题 / 逐条推送的改动。
set -e

echo "=== 1) 解包并安装 ==="
rm -rf /tmp/cld
mkdir -p /tmp/cld
tar -xf /tmp/celldeploy.tar -C /tmp/cld
sh /tmp/cld/deploy-cell/install.sh

echo
echo "=== 2) 语法检查 ==="
python3 -c "import py_compile; py_compile.compile('/usr/bin/smstrun.py', doraise=True)" && echo PY_OK
sh -n /usr/bin/smstrun.sh && echo SH_OK

echo
echo "=== 3) 落地文件指纹 ==="
md5sum /usr/bin/smstrun.py /usr/bin/smstrun.sh

echo
echo "=== 4) 标题提取 ==="
sh /tmp/verify_title_on_router.sh

echo
echo "=== 5) merge_sms 跨轮攒段（合成数据）==="
sh /tmp/verify_merge_on_router.sh

echo
echo "=== 6) 进程与日志 ==="
ps w | grep '[s]mstrun.py'
tail -n 15 /tmp/smstrun.log
