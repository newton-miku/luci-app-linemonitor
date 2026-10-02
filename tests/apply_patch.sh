#!/bin/sh
# 在路由器上执行：解包 /tmp/lmpatch.tar 并覆盖三个文件（不动 targets.conf）
set -e

cd /tmp
rm -rf lmp
mkdir -p lmp
tar -xf lmpatch.tar -C lmp

echo "--- 解包内容 ---"
find lmp -type f | sort

cp lmp/www/lm/line.html        /www/lm/line.html
cp lmp/www/lm/config.html      /www/lm/config.html
cp lmp/usr/bin/lm_config_json.sh /usr/bin/lm_config_json.sh
chmod +x /usr/bin/lm_config_json.sh

echo "--- 安装后 md5 ---"
md5sum /www/lm/line.html /www/lm/config.html /usr/bin/lm_config_json.sh

echo "--- targets.conf 是否被动过 ---"
ls -l /etc/line-monitor/targets.conf
echo "--- 生成 config.json 的接口是否存在 ---"
ls -l /www/cgi-bin/lm-config 2>/dev/null || echo "无 /www/cgi-bin/lm-config"
