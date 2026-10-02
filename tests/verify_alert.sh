#!/bin/sh
echo "=== disabled run (should print nothing) ==="
/usr/bin/lm_alert.sh
echo "run_rc=$?"
echo "=== state file ==="
ls -l /tmp/lm_alert.state 2>/dev/null || echo "no state file"
echo "=== --test with empty url ==="
/usr/bin/lm_alert.sh --test
echo "test_rc=$?"
echo "=== router targets.conf (all non-comment lines) ==="
grep -v '^#' /etc/line-monitor/targets.conf | grep -v '^$'
echo "=== cgi alerttest ==="
REQUEST_METHOD=GET QUERY_STRING=alerttest /www/cgi-bin/lm-config
echo "cgi_rc=$?"
echo "=== page sizes ==="
ls -l /www/lm/config.html /www/lm/line.html
echo "=== tail log ==="
tail -n 1 /www/lm/history.log | cut -c1-200
echo
