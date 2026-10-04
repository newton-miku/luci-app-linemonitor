#!/bin/sh
# 给「内置蜂窝」（luci-app-WTModem）的短信转发加飞书 webhook 后端。
#
# 原来的转发链路是 smstrun.py -> pushplus 公众号（PPS+平台）。
# 这里把 smstrun.py 换成支持双后端的版本：配了飞书就推飞书，否则照旧推 PPS+。
#
# 装完要重启转发进程：smstrun.py 由 /etc/init.d/modeminit 拉起，
# kill 掉之后不会自己回来，所以这里手动起一个。

set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
FEISHU_URL="${FEISHU_URL:-}"

echo "==> 备份原有文件到 /root/cell-sms-backup/"
mkdir -p /root/cell-sms-backup
# 只在还没有备份时备份，避免把「已被 patch 过的版本」当成原件覆盖掉
for f in /usr/bin/smstrun.py /usr/bin/smstrun.sh /etc/init.d/modeminit /usr/lib/lua/luci/model/cbi/modem.lua; do
    bak="/root/cell-sms-backup/$(basename "$f").bak"
    if [ -f "$f" ] && [ ! -f "$bak" ]; then
        cp "$f" "$bak" && echo "    $f -> $bak"
    elif [ -f "$bak" ]; then
        echo "    $f（已有备份，保留）"
    fi
done

echo "==> 安装 smstrun.py（支持飞书 / PPS+ 双后端 + 长短信分段合并）"
cp "$SRC/usr/bin/smstrun.py" /usr/bin/smstrun.py
chmod +x /usr/bin/smstrun.py

# smstrun.sh 也必须换：原厂版本用 `AT+CMGL=0` 只列未读短信，而本模组收到新短信
# 之后立刻就是 REC READ 状态，于是原厂脚本恒读到空、转发链路永远不触发。
echo "==> 安装 smstrun.sh（原厂版恒读到空，必须替换）"
cp "$SRC/usr/bin/smstrun.sh" /usr/bin/smstrun.sh
chmod +x /usr/bin/smstrun.sh

cp "$SRC/usr/bin/smstrun-restart.sh" /usr/bin/smstrun-restart.sh
chmod +x /usr/bin/smstrun-restart.sh
cp "$SRC/usr/bin/patch-modem-lua.py" /usr/bin/patch-modem-lua.py
chmod +x /usr/bin/patch-modem-lua.py

if [ -n "$FEISHU_URL" ]; then
    echo "==> 写入飞书 webhook 到 /usr/bin/smstrun-feishu.conf"
    printf '%s' "$FEISHU_URL" > /usr/bin/smstrun-feishu.conf
    chmod 600 /usr/bin/smstrun-feishu.conf
elif [ -f /usr/bin/smstrun-feishu.conf ]; then
    echo "==> 保留已有 /usr/bin/smstrun-feishu.conf"
else
    echo "==> 未提供飞书 URL，先写个空占位（填上才会启用飞书）"
    : > /usr/bin/smstrun-feishu.conf
    chmod 600 /usr/bin/smstrun-feishu.conf
fi

echo "==> 给内置蜂窝的 LuCI 页面加「飞书 Webhook」输入框"
python3 /usr/bin/patch-modem-lua.py

# uhttpd 的嵌入式 Lua 会缓存已 require 的 CBI model，改完 modem.lua 必须重启它，
# 否则点「应用」时跑的仍是内存里的旧版本（表现为：填了值也写不进 conf）。
echo "==> 重启 uhttpd 让 LuCI 重新加载 modem.lua"
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
sleep 2

echo "==> 重启短信转发进程"
# 这台固件没有 pkill，用 ps + kill 兜底
for p in $(ps w | grep '[s]mstrun.py' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
sleep 1
rm -f /tmp/smstrun.lock
nohup python3 /usr/bin/smstrun.py >/tmp/smstrun.log 2>&1 &
sleep 2

if ps w 2>/dev/null | grep -q '[s]mstrun.py'; then
    echo "==> 转发进程已启动"
    tail -n 5 /tmp/smstrun.log 2>/dev/null || true
else
    echo "==> 警告：转发进程没起来，看 /tmp/smstrun.log"
    tail -n 20 /tmp/smstrun.log 2>/dev/null || true
fi

echo
echo "完成。飞书 webhook 配置文件：/usr/bin/smstrun-feishu.conf"
echo "改完 URL 后执行：sh /usr/bin/smstrun-restart.sh"
