#!/bin/sh
echo "=== A) 新短信的第 2/3/4 段在不在模组里？ ==="
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^' | while IFS= read -r line; do
  case "$line" in +CMGL:*) continue;; esac
  [ -n "$line" ] || continue
  echo "$line" | pdu_decoder 2>/dev/null | grep -E 'Reference number: 0$|SMS segment' | tr -d '\r'
done | head -n 20
echo
echo "=== B) ref=0 的全部段（含时间/发件人）==="
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep -v '^\^' | while IFS= read -r line; do
  case "$line" in +CMGL:*) continue;; esac
  [ -n "$line" ] || continue
  d=$(echo "$line" | pdu_decoder 2>/dev/null)
  case "$d" in *"Reference number: 0"*)
    echo "-----"
    echo "$d" | cut -c1-120
    ;;
  esac
done
echo
echo "=== C) 那条空发件人的 idx=14 是哪来的 ==="
sendat 1 AT+CMGL=4 2>/dev/null | tr -d '\r' | grep '^+CMGL: 14,' | cat -A | head -n 3
echo
echo "=== D) smstrun.sh 里 cur 的取值：awk -F '[ ,]' 对 +CMGL: 14,1,,43 的输出 ==="
printf '%s\n' '+CMGL: 14,1,,43' | awk -F '[ ,]' '{print "字段2=[" $2 "]"}'
