echo "########## modem.lua 540-600（apply_notifications_websocket.write 上下文）##########"
sed -n '540,600p' /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "########## modem.lua 640-700（websocket_server 启动与 config.json）##########"
sed -n '640,700p' /usr/lib/lua/luci/model/cbi/modem.lua