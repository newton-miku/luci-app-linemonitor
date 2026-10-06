import json
import os
import re
import signal
import socket
import sys
import time
import requests
import subprocess
from datetime import datetime

# nohup 启动时 stdout 是全缓冲的，print 的内容要攒满 4~8 KB 才落盘，
# 于是 /tmp/smstrun.log 长时间是空的、攒段过程完全看不到。改成行缓冲。
try:
    sys.stdout.reconfigure(line_buffering=True)
except Exception:
    pass

# 飞书自定义机器人 webhook。填了这个文件就推飞书，不再推 PPS+；
# 两者都填时飞书优先（用户要的是「替代」）。
FEISHU_CONF = "/usr/bin/smstrun-feishu.conf"
TOKEN_CONF = "/usr/bin/smstrun.conf"
TITLE_CONF = "/usr/bin/smstrun-title.conf"
SUMMARY_PATH = "/tmp/smstrunsum.conf"
LOCK_FILE = "/tmp/smstrun.lock"

# tailscale 的 MagicDNS 会把 /etc/resolv.conf 改成指向 100.100.100.100，
# 那台 DNS 一旦不可达，路由器上所有域名都解析不了（ping IP 正常、curl 域名超时）。
# 出网前先用本地 dnsmasq（127.0.0.1）把飞书域名解析一次写进 /etc/hosts 兜底。
HOSTS_MARK = " # smstrun-feishu"


def resolve_via(ns, host):
    """用指定的 DNS 服务器解析域名，返回第一个 IPv4 地址。"""
    for cmd in (['nslookup', host, ns], ['nslookup', host]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
        except Exception:
            continue
        ips = re.findall(r"^Address \d+:\s*(\d+\.\d+\.\d+\.\d+)", out, re.M)
        if ips:
            return ips[0]
    return None


def clean_hosts_entry():
    try:
        with open("/etc/hosts", "r") as f:
            lines = f.readlines()
    except Exception:
        return
    kept = [l for l in lines if HOSTS_MARK not in l]
    if len(kept) != len(lines):
        try:
            with open("/etc/hosts", "w") as f:
                f.writelines(kept)
        except Exception as e:
            print("清理 /etc/hosts 失败: ", e)


def ensure_hosts_entry(host):
    """先清掉自己以前写的条目，再判断系统 DNS 是否真的能解析；
    不行就用本地 dnsmasq 兜底写 /etc/hosts。

    必须先清：/etc/hosts 里的条目本身就能让 getaddrinfo 成功，
    不清的话会误判成「系统 DNS 正常」，反手把自己的兜底条目删掉。
    """
    clean_hosts_entry()
    try:
        socket.getaddrinfo(host, 443, socket.AF_INET)
        return True
    except Exception:
        pass
    for ns in ("127.0.0.1", "223.5.5.5", "114.114.114.114"):
        ip = resolve_via(ns, host)
        if not ip:
            continue
        try:
            # 写之前再清一次：转发进程启动与手动重置可能几乎同时跑，
            # 交错时两边都会以为自己是唯一，留下重复行（同一个 IP，无害但不干净）。
            clean_hosts_entry()
            with open("/etc/hosts", "a") as f:
                f.write("%s %s%s\n" % (ip, host, HOSTS_MARK))
            print("系统 DNS 不可用，已把 %s -> %s 写入 /etc/hosts 兜底。" % (host, ip))
            return True
        except Exception as e:
            print("写 /etc/hosts 失败: ", e)
            return False
    print("无法解析 %s，飞书推送可能失败。" % host)
    return False


def read_conf(path, default=None):
    try:
        with open(path, "r") as file:
            val = file.read().strip()
            return val if val else default
    except FileNotFoundError:
        return default


# 短信签名形如【腾讯科技】【中国移动】，几乎都贴在正文最前面。
SIGN_RE = re.compile(r'[【\[]([^】\]\n]{1,20})[】\]]')


def read_title():
    """smstrun-title.conf 里配的固定标题。没配就是空串——空串代表「不设标题」。"""
    return read_conf(TITLE_CONF, "")


def sms_title(text):
    """给一条短信挑标题。

    优先用短信自带的签名（【腾讯科技】/【中国移动】这类），提不到再退回
    smstrun-title.conf 里配的固定标题，都没配就返回空串。空标题时飞书 post
    不带 title 字段，卡片上不会多出一行没意义的占位文字。
    """
    m = SIGN_RE.search(text or '')
    if m:
        inner = m.group(1).strip()
        if inner:
            return '【%s】' % inner
    return read_title()


def write_summary_to_file(count, out):
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        with open(SUMMARY_PATH, 'a') as file:
            file.write(f"本次转发时间: {current_time}\n")
            file.write(f"已完成: {count}次短信转发\n")
            file.write(f"转发内容:\n\n{out}\n")
            file.write("\n")
    except Exception as e:
        print(f"写入文件失败: {e}")


def check_lock(lock_file):
    if os.path.exists(lock_file):
        print("脚本已经在运行中。")
        return False
    try:
        with open(lock_file, 'w') as file:
            file.write(str(os.getpid()))
        return True
    except Exception as e:
        print("无法创建锁文件: ", e)
        return False


def remove_lock(lock_file):
    try:
        os.remove(lock_file)
    except Exception as e:
        print("无法删除锁文件: ", e)


def push_feishu(message, url, title):
    """飞书自定义机器人：post 富文本，title 单独一行，正文整段塞进一个 text 节点。

    title 为空时不带这个字段——带上空串飞书会在卡片顶部渲染一行空标题。
    第一次失败（多半是域名解析不出来）就先补一次 /etc/hosts 兜底再重试一发。
    """
    zh_cn = {"content": [[{"tag": "text", "text": message}]]}
    if title:
        zh_cn["title"] = title
    payload = {"msg_type": "post", "content": {"post": {"zh_cn": zh_cn}}}
    for attempt in (1, 2):
        try:
            response = requests.post(url, json=payload, timeout=15)
            print("Feishu response:\n", response.text)
            try:
                return response.json().get("StatusCode") == 0
            except Exception:
                # 返回体不是 JSON 时退化成看 HTTP 状态码
                return response.status_code == 200
        except Exception as e:
            print("Error occurred (%d/2): %s" % (attempt, str(e)))
            if attempt == 1:
                ensure_hosts_entry("open.feishu.cn")
    return False


def push_pushplus(message, token, title):
    url = "http://www.pushplus.plus/send"
    data = {"token": token, "title": title or "短信转发", "content": message}
    try:
        response = requests.post(url, json=data, timeout=15)
        print("Response:\n", response.json())
        return True
    except Exception as e:
        print("Error occurred: ", str(e))
        return False


def valid_sender(s):
    """发件人必须是 5~20 位的数字（可带前导 +）。

    本模组 ME 里有一批未初始化的坏槽位，`AT+CMGL=4` 会把它们（连同行尾的 OK、
    AT 回显）一起列出来，pdu_decoder 解出的发件人是乱码：`?7000000100000000`、
    `6=88<4>4:3757435?>08=?=698:5<<;88<`、`<>67>705=025::25;`、`41?`。
    真号码最短是 10086 这种 5 位短号，所以长度下限取 5。
    """
    return bool(re.fullmatch(r'\+?\d{5,20}', s or ''))


def valid_time(t):
    """发件时间形如 `10/05/26 03:51:55`，年份必须是 2018~2035。

    坏槽位的时间戳在 1990~2099 之间乱跳（实测 05/31/92、12/06/99、12/29/97、
    08/03/64、07/31/04、12/09/15），真短信的时间总是当前年份附近。
    """
    m = re.match(r'(\d{2})/(\d{2})/(\d{2})\s+\d{2}:\d{2}:\d{2}', t or '')
    if not m:
        return False
    return 18 <= int(m.group(3)) <= 35


def parse_blocks(out):
    """把 smstrun.sh 的输出切成一条条短信。

    每个块长这样（块之间用一串横线分隔）：
        第2条短信
        发件人:1065896652061002
        发件时间:10/03/26 17:31:45
        Reference number: 14
        SMS segment 1 of 2
        正文第一段
        ------------------------------------------------------
    """
    blocks = []
    cur = None
    for raw in out.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith('第') and line.endswith('条短信'):
            # 只留数字，别把「第2条短信」整个当标题，最后拼出来会是「第第2条短信条短信」
            m = re.search(r'(\d+)', line)
            cur = {'idx': m.group(1) if m else '?', 'body': []}
            continue
        if set(line) == {'-'}:
            if cur:
                blocks.append(cur)
            cur = None
            continue
        if cur is None:
            continue
        if line.startswith('发件人:'):
            cur['from'] = line[len('发件人:'):].strip()
        elif line.startswith('发件时间:'):
            cur['time'] = line[len('发件时间:'):].strip()
        elif line.startswith('Reference number:'):
            cur['ref'] = line.split(':', 1)[1].strip()
        elif line.startswith('SMS segment'):
            m = re.search(r'segment\s+(\d+)\s+of\s+(\d+)', line)
            if m:
                cur['seg'] = int(m.group(1))
                cur['segs'] = int(m.group(2))
        else:
            cur['body'].append(line.strip())
    if cur:
        blocks.append(cur)
    # 双保险：smstrun.sh 已按「PDU 十六进制 / 发件人 / 年份 / 段数」四道过滤过一遍，
    # 这里再挡一次。万一机器上跑的还是没带过滤的老 smstrun.sh，靠这层兜底。
    return [b for b in blocks
            if valid_sender(b.get('from')) and valid_time(b.get('time'))
            and int(b.get('segs', 0) or 0) <= 20]


# 长短信分段缓冲：key -> {'segs': 总段数, 'parts': {段号: 正文}, 'idx': 首段序号, 'time': 发件时间}
# 必须跨轮次保留，因为 3 段短信可能分三次采集才到齐，攒齐了再一次性推出去。
_pending = {}


def merge_sms(out):
    """把长短信的多段拼成完整一条。

    内置蜂窝的 web 页（/usr/share/modem/smsc.sh）其实是逐条 PDU 单独解码、直接显示的，
    分段也是散的；这里按「发件人 + Reference number」归组（没有 ref 就退回「发件人 +
    发件时间」），攒齐所有段之后才拼成完整一条推送，避免一条长短信被拆成三条碎片消息。

    攒不齐的（长时间只到了一部分，比如模组已经清掉更早的段）超过 30 分钟就按现有内容
    推出去并清掉缓冲，免得一直卡着不发。
    """
    blocks = parse_blocks(out)
    if not blocks:
        return []                     # 本轮没有新短信

    # 先按分组键把本轮拿到的段落并进缓冲
    for b in blocks:
        sender = b.get('from', '')
        key = (sender, b['ref']) if b.get('ref') else (sender, b.get('time', ''))
        slot = _pending.setdefault(key, {'segs': 0, 'parts': {}, 'idx': b.get('idx', '?'),
                                         'time': b.get('time', ''), 'at': time.time()})
        if b.get('segs'):
            slot['segs'] = max(slot['segs'], b['segs'])
        slot['parts'][b.get('seg', 0)] = ''.join(b['body'])
        if not slot['time'] and b.get('time'):
            slot['time'] = b['time']

    # 组装：攒齐的立即推；没攒齐但超时的也推（按已有内容）
    out_lines = []
    for key in list(_pending.keys()):
        slot = _pending[key]
        total = slot['segs']
        got = len(slot['parts'])
        stale = time.time() - slot['at'] > 1800
        if total and got < total and not stale:
            print("长短信分段未齐：发件人%s ref=%s 已收到 %d/%d 段，继续等待。"
                  % (key[0], key[1], got, total))
            continue                      # 还没齐，继续等下一轮
        if total and got < total:
            print("长短信分段超时：发件人%s ref=%s 只收到 %d/%d 段，按现有内容推送。"
                  % (key[0], key[1], got, total))
        body = ''.join(slot['parts'][k] for k in sorted(slot['parts']))
        sender = key[0]
        lines = ['第%s条短信' % slot['idx']]
        lines.append('发件人:%s' % sender)
        if slot['time']:
            lines.append('发件时间:%s' % slot['time'])
        if total and total > 1:
            lines.append('（长短信 %d 段%s）' % (total, '已完整拼接' if got >= total else '只收到 %d 段' % got))
        lines.append(body)
        out_lines.append('\n'.join(lines))
        del _pending[key]

    if not out_lines:
        # 全部还差段：必须返回空列表，不能把原始碎片回传——调用方是靠返回内容判断
        # 要不要推送的，返回碎片就等于把没拼全的分段当成完整短信推出去。
        return []
    return out_lines


def run_smstrun():
    """跑一轮采集，返回 stdout；卡住或出错返回 None。

    sendat / pdu_decoder 都可能挂住（pdu_decoder 收不到换行时会一直挂在 read 上）。
    超时后用 killpg 把整个进程组杀掉——只杀 sh 的话，它派生的 sendat / pdu_decoder
    会变成孤儿继续挂着，一轮轮积累（实测见过同时 4 个 sh /usr/bin/smstrun.sh）。
    start_new_session=True 让子进程单独成组，才能一次性收干净。
    """
    proc = subprocess.Popen(['sh', '/usr/bin/smstrun.sh'],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            proc.kill()
        try:
            proc.communicate(timeout=5)
        except Exception:
            pass
        print("smstrun.sh 执行超过 20 秒，已杀进程组并跳过本轮。")
        return None
    if proc.returncode != 0:
        print("smstrun.sh 返回码 %s。stderr: %s"
              % (proc.returncode, (stderr or '').strip()[:200]))
        return None
    return stdout


def forward():
    if not check_lock(LOCK_FILE):
        return

    try:
        feishu_url = read_conf(FEISHU_CONF)
        token = read_conf(TOKEN_CONF)
        if not feishu_url and not token:
            print("飞书 webhook 和 PPS+ token 都没配，程序退出。")
            print("飞书 URL 写到 %s，PPS+ token 写到 %s。" % (FEISHU_CONF, TOKEN_CONF))
            return
        if feishu_url:
            ensure_hosts_entry("open.feishu.cn")
            print("已启用飞书推送。")
        else:
            print("已启用 PPS+ 推送。")
        print("Enjoy! 已完成测试并开启转发功能，重启后完成开机自启。")

        count = 0
        while True:
            try:
                raw = run_smstrun()
                if raw is not None:
                    msgs = merge_sms(raw)
                    if not msgs:
                        print("未检测到新消息，继续检测...")
                    for msg in msgs:
                        # 逐条推送：标题取自各自的签名，多条短信不会共用一个标题
                        title = sms_title(msg)
                        if feishu_url:
                            push_feishu(msg, feishu_url, title)
                        else:
                            push_pushplus(msg, token, title)
                        count += 1
                        write_summary_to_file(count, msg)
            except UnicodeDecodeError as e:
                print(f"解码错误: {e}. 尝试重新运行。")
            except Exception as e:
                print("发生未处理异常: ", str(e))
            time.sleep(5)
    finally:
        remove_lock(LOCK_FILE)


if __name__ == '__main__':
    forward()
