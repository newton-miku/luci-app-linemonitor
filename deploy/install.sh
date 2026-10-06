#!/bin/sh
# 线路监测程序 —— 在路由器上安装
# 用法：sh /tmp/lmd/deploy/install.sh
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p /etc/line-monitor
mkdir -p /www/lm/lib
mkdir -p /www/cgi-bin

# 配置：已存在就不覆盖，免得升级时把用户改过的配置冲掉
if [ -f /etc/line-monitor/targets.conf ]; then
    echo "保留已有配置 /etc/line-monitor/targets.conf"
    cp -f /etc/line-monitor/targets.conf /etc/line-monitor/targets.conf.keep
else
    cp "$SRC/etc/line-monitor/targets.conf" /etc/line-monitor/targets.conf
fi

cp "$SRC/usr/bin/line_monitor.sh"    /usr/bin/line_monitor.sh
cp "$SRC/usr/bin/tcp_stream.sh"      /usr/bin/tcp_stream.sh
cp "$SRC/usr/bin/line_daemon.sh"     /usr/bin/line_daemon.sh
cp "$SRC/usr/bin/lm_config_json.sh"  /usr/bin/lm_config_json.sh
cp "$SRC/usr/bin/lm_alert.sh"        /usr/bin/lm_alert.sh
cp "$SRC/usr/bin/lm_rate.sh"         /usr/bin/lm_rate.sh
chmod +x /usr/bin/line_monitor.sh /usr/bin/tcp_stream.sh \
         /usr/bin/line_daemon.sh /usr/bin/lm_config_json.sh \
         /usr/bin/lm_alert.sh /usr/bin/lm_rate.sh

cp "$SRC/www/lm/line.html"    /www/lm/line.html
cp "$SRC/www/lm/config.html"  /www/lm/config.html
# lib 里既有 Chart.js 的 js，也有 antd 深色主题的 css，要一起拷
cp "$SRC/www/lm/lib/"*        /www/lm/lib/

# 新版看板：本机 `npm run build` 出来的 React + antd v5 + ProComponents 产物。
# 老 line.html 继续留着当退路，两边读的是同一份 history.log/config.json。
if [ -d "$SRC/www/lm/app" ]; then
    rm -rf /www/lm/app
    mkdir -p /www/lm/app
    cp -r "$SRC/www/lm/app/." /www/lm/app/
fi

cp "$SRC/www/cgi-bin/lm-config" /www/cgi-bin/lm-config
cp "$SRC/www/cgi-bin/lm-rate"   /www/cgi-bin/lm-rate
chmod +x /www/cgi-bin/lm-config /www/cgi-bin/lm-rate

cp "$SRC/etc/init.d/linemon" /etc/init.d/linemon
chmod +x /etc/init.d/linemon

# 修「本机电信 IPv6 被 mwan3 策略路由丢弃」（看板上 v6-pppoe-wan2|* 恒 FAIL 的假阴性）
# 详见 deploy/etc/hotplug.d/iface/99-lm-v6-rule 头部注释
mkdir -p /etc/hotplug.d/iface
cp "$SRC/etc/hotplug.d/iface/99-lm-v6-rule" /etc/hotplug.d/iface/99-lm-v6-rule
chmod +x /etc/hotplug.d/iface/99-lm-v6-rule
sh /etc/hotplug.d/iface/99-lm-v6-rule apply 2>/dev/null || true

# LuCI 入口：菜单 + 权限 + 客户端 JS 视图（把看板嵌进 OpenWrt 管理界面）
# 本固件 LuCI 走客户端渲染，视图必须放在 /www/luci-static/resources/view/<path>.js，
# 旧的 /usr/lib/lua/luci/view/<path>.htm 服务端模板路径无效（会 404）。
cp "$SRC/usr/share/luci/menu.d/luci-app-linemon.json" /usr/share/luci/menu.d/luci-app-linemon.json
cp "$SRC/usr/share/rpcd/acl.d/luci-app-linemon.json"  /usr/share/rpcd/acl.d/luci-app-linemon.json

mkdir -p /www/luci-static/resources/view/linemon
cp "$SRC/www/luci-static/resources/view/linemon/status.js" /www/luci-static/resources/view/linemon/status.js
cp "$SRC/www/luci-static/resources/view/linemon/config.js" /www/luci-static/resources/view/linemon/config.js

# 清掉早期版本装错位置的服务端模板
rm -rf /usr/lib/lua/luci/view/linemon

# 清缓存必须用通配符：LuCI 的索引缓存文件名带随机后缀
# （如 /tmp/luci-indexcache.41DlbICXc.JLUTsUyO7MQ..json），写死文件名删不掉。
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.json
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache

# 生成看板用的 config.json
[ -x /usr/bin/lm_config_json.sh ] && /usr/bin/lm_config_json.sh || true

echo "安装开机自启"
/etc/init.d/linemon enable
/etc/init.d/linemon restart

# 让新菜单立刻出现在 LuCI 里
/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true
echo "完成：LuCI「服务 → 线路监测」"
echo "注：侧栏菜单树由客户端缓存在 sessionStorage（硬刷新清不掉）。"
echo "    若「服务选项」下暂时看不到「线路监测」，关闭该标签页重新打开即可，"
echo "    或直接访问一次 /cgi-bin/luci/admin/services/linemon/status 自动修复。"
