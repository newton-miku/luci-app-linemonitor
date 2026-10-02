echo "=== modem 相关 menu.d 条目 ==="
grep -l 'modem' /usr/share/luci/menu.d/*.json 2>/dev/null
echo "---"
for f in /usr/share/luci/menu.d/*.json; do
  if grep -q 'modem' "$f" 2>/dev/null; then
    echo "### $f"
    grep -A3 -B1 'modem' "$f" | head -40
  fi
done
echo
echo "=== 找 cbi/modem.lua 对应的 controller ==="
grep -rn 'cbi("modem")' /usr/lib/lua/luci/controller/ 2>/dev/null
grep -rn 'cbi("modem")' /usr/lib/lua/luci/ 2>/dev/null | head -10
echo
echo "=== lua controller 里的 modem 入口 ==="
ls /usr/lib/lua/luci/controller/ | head -40