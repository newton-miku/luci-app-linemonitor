import json
import os
import re
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


def read_title():
    return read_conf(TITLE_CONF, "CPE短信转发标题未定义")


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

    第一次失败（多半是域名解析不出来）就先补一次 /etc/hosts 兜底再重试一发。
    """
    payload = {
        "msg_type": "post",
        "content": {
            "post": {
                "zh_cn": {
                    "title": title,
                    "content": [[{"tag": "text", "text": message}]]
                }
            }
        }
    }
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
    data = {"token": token, "title": title, "content": message}
    try:
        response = requests.post(url, json=data, timeout=15)
        print("Response:\n", response.json())
        return True
    except Exception as e:
        print("Error occurred: ", str(e))
        return False


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
    return blocks


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
        return out                    # 本轮没有新短信，原样返回（通常就是空串）

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
        lines.append('------------------------------------------------------')
        out_lines.append('\n'.join(lines))
        del _pending[key]

    if not out_lines:
        # 全部还差段：必须返回空串，不能把原始碎片回传。
        # smstrun.py 是靠 "发件人" in out 判断要不要推送的，返回碎片就等于把没拼全的
        # 分段当成完整短信推出去，正是这次要修的问题。
        return ''
    return '\n'.join(out_lines)


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
                # 45 秒上限：smstrun.sh 里有 sendat / pdu_decoder，两者都可能卡住
                # （实测 pdu_decoder 收不到换行时会一直挂在 read 上），
                # 不加超时的话这一层 while 循环会永久卡死、再也收不到短信。
                result = subprocess.run(['sh', '/usr/bin/smstrun.sh'],
                                        capture_output=True, text=True, check=True,
                                        timeout=45)
                out = merge_sms(result.stdout)
                if "发件人" in out:
                    title = read_title()
                    if feishu_url:
                        push_feishu(out, feishu_url, title)
                    else:
                        push_pushplus(out, token, title)
                    count += 1
                    write_summary_to_file(count, out)
                else:
                    print("未检测到新消息，继续检测...")
            except subprocess.CalledProcessError as e:
                print(f"执行命令失败: {e}. 返回值: {e.returncode}. 错误信息: {e.stderr}")
            except subprocess.TimeoutExpired:
                print("smstrun.sh 执行超过 45 秒，已跳过本轮（sendat/pdu_decoder 卡住）。")
            except UnicodeDecodeError as e:
                print(f"解码错误: {e}. 尝试重新运行。")
            except Exception as e:
                print("发生未处理异常: ", str(e))
            time.sleep(5)
    finally:
        remove_lock(LOCK_FILE)


if __name__ == '__main__':
    forward()
