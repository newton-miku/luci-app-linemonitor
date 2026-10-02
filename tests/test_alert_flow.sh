#!/bin/sh
# 造异常验证去抖与恢复通知：把阈值压到 1ms，所有目标都会「超标」
C=/etc/line-monitor/targets.conf

echo "=== 阈值压到 1ms（全部目标算异常）==="
sed -i 's/^ALERT_MAX_MS=.*/ALERT_MAX_MS=1/' "$C"
grep '^ALERT_MAX_MS' "$C"

echo "--- 第 1 次（连续 1，不该推）---"
/usr/bin/lm_alert.sh; echo "rc=$?"
echo "--- 第 2 次（连续 2，不该推）---"
/usr/bin/lm_alert.sh; echo "rc=$?"
echo "--- 第 3 次（连续 3 = DEBOUNCE，该推了）---"
/usr/bin/lm_alert.sh; echo "rc=$?"
echo "--- 第 4 次（已报过且未到 COOLDOWN，该沉默）---"
/usr/bin/lm_alert.sh; echo "rc=$?"

echo "=== 状态前 4 行 ==="
/usr/bin/lm_alert.sh --status | head -4
echo "=== 状态行数 ==="
/usr/bin/lm_alert.sh --status | wc -l

echo "=== 阈值还原 300，下一轮应推「已恢复」==="
sed -i 's/^ALERT_MAX_MS=.*/ALERT_MAX_MS=300/' "$C"
grep '^ALERT_MAX_MS' "$C"
/usr/bin/lm_alert.sh; echo "rc=$?"

echo "=== 恢复后状态前 4 行 ==="
/usr/bin/lm_alert.sh --status | head -4
