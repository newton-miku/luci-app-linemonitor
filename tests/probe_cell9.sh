echo "=== modem.lua 里的函数定义与 write/save 回调 ==="
grep -n -E 'function|:write|:parse|entry|formvalue|m:formvalue|save' /usr/lib/lua/luci/model/cbi/modem.lua | head -40
echo
echo "=== modem.lua 头部 1-40 行 ==="
sed -n '1,40p' /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "=== 文件总行数 ==="
wc -l /usr/lib/lua/luci/model/cbi/modem.lua
echo
echo "=== 有没有 map:section 之外的 Lua 侧写文件动作 ==="
grep -n -E 'writefile|io\.open|os\.execute|/usr/bin/' /usr/lib/lua/luci/model/cbi/modem.lua | head -20