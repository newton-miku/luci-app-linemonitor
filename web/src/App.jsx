import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PageContainer } from '@ant-design/pro-components';
import { Button, Space } from 'antd';
import Overview from './pages/Overview.jsx';
import ExitPage from './pages/ExitPage.jsx';
import TcpPage from './pages/TcpPage.jsx';
import { loadConfig, loadHistory, loadTcp, loadRate, historySig } from './api.js';
import { WINDOWS, fmtFull } from './stats.js';
import { dataSpan } from './chart.js';

const LS_SMOOTH = 'lm_smooth';
const POLL_MS = 60000;
// 速率是秒级数据，用单独的短周期轮询，跟上面那份 60 秒的历史日志分开。
// 2 秒一次、每次只读一个几十字节的 JSON，比历史日志便宜得多。
const RATE_POLL_MS = 2000;

export default function App() {
  const [cfg, setCfg] = useState(null);
  const [hist, setHist] = useState([]);
  const [tcp, setTcp] = useState([]);
  const [rate, setRate] = useState({ ts: 0, rates: [] });
  const [tab, setTab] = useState('overview');
  const [smooth, setSmooth] = useState(() => localStorage.getItem(LS_SMOOTH) === '1');
  const [statWin, setStatWin] = useState('all');
  const [range, setRange] = useState(null);
  // 窗口是不是被人手拖出来的。预设按钮的高亮只看这个，不看窗口宽度，
  // 否则拖到刚好 6 小时会把「6 小时」按钮点亮，误导。
  const [rangeCustom, setRangeCustom] = useState(false);
  const sigRef = useRef('');

  const applySpan = useCallback((h, winKey) => {
    const span = dataSpan(h);
    if (!span.max) return null;
    const w = WINDOWS.find((x) => x.key === winKey) || WINDOWS[0];
    const r = w.ms
      ? { min: Math.max(span.min, span.max - w.ms), max: span.max }
      : { min: span.min, max: span.max };
    setRange(r);
    return r;
  }, []);

  useEffect(() => {
    (async () => {
      const c = await loadConfig();
      c.th = {
        maxWarn: c.th_max_warn, maxBad: c.th_max_bad,
        sdWarn: c.th_sd_warn, sdBad: c.th_sd_bad,
      };
      const h = await loadHistory();
      setCfg(c);
      setHist(h);
      // 默认给全量窗口：pro demo 那条 dataZoom 滑块就是铺满轨道的，
      // 一上来只留最后 1 小时的话两个把手会挤在右端，反而看不出是个滑块。
      applySpan(h, 'all');
      setTcp(await loadTcp());
      setRate(await loadRate());
      sigRef.current = await historySig();
    })();
  }, [applySpan]);

  // 速率短轮询：只在看板可见时跑，切到后台就停，省路由器的连接数
  useEffect(() => {
    let alive = true;
    const tick = async () => {
      if (document.hidden) return;
      const r = await loadRate();
      if (alive) setRate(r);
    };
    const t = setInterval(tick, RATE_POLL_MS);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);

  // 轮询：指纹没变就什么都不做，避免每分钟白刷一遍上千行
  useEffect(() => {
    const t = setInterval(async () => {
      const sig = await historySig();
      if (sig && sig !== sigRef.current) {
        sigRef.current = sig;
        setHist(await loadHistory());
        setTcp(await loadTcp());
      }
    }, POLL_MS);
    return () => clearInterval(t);
  }, []);

  const onPickWin = useCallback((ms) => {
    const span = dataSpan(hist);
    if (!span.max) return;
    setRange(ms ? { min: Math.max(span.min, span.max - ms), max: span.max } : { min: span.min, max: span.max });
    setRangeCustom(false);
    const w = WINDOWS.find((x) => x.ms === ms);
    if (w) setStatWin(w.key);
  }, [hist]);

  const onRangeChange = useCallback((r) => {
    if (!r || !Number.isFinite(r.min) || !Number.isFinite(r.max)) return;
    setRange(r);
    setRangeCustom(true);
  }, []);

  const exits = cfg?.exits || [];

  const tabList = useMemo(
    () => [
      { key: 'overview', tab: '总览' },
      ...exits.map((e) => ({ key: 'ex:' + e.if, tab: e.label || e.if })),
      { key: 'tcp', tab: '实时 TCP 流' },
    ],
    [exits]
  );

  const onToggleSmooth = () => {
    const next = !smooth;
    setSmooth(next);
    localStorage.setItem(LS_SMOOTH, next ? '1' : '0');
  };

  const last = hist.length ? hist[hist.length - 1].ts : 0;

  let body = null;
  if (!cfg) {
    body = <div style={{ padding: 48, textAlign: 'center', color: 'rgba(255,255,255,.45)' }}>加载中…</div>;
  } else if (tab === 'overview') {
    body = <Overview cfg={cfg} hist={hist} rate={rate} range={range} onOpenExit={setTab} />;
  } else if (tab === 'tcp') {
    body = <TcpPage cfg={cfg} tcp={tcp} />;
  } else {
    const e = exits.find((x) => 'ex:' + x.if === tab);
    body = e ? (
      <ExitPage
        cfg={cfg} hist={hist} exit={e} range={range}
        onRangeChange={onRangeChange} statWin={statWin} onPickWin={onPickWin}
        rangeCustom={rangeCustom} smooth={smooth}
      />
    ) : null;
  }

  return (
    <PageContainer
      className="lm-pc"
      ghost
      header={{
        breadcrumb: null,
        title: cfg?.title || '线路质量监测看板',
        subTitle: cfg?.subtitle || '',
        extra: (
          <Space size={12}>
            <span className="lm-updated">
              {last ? '延迟更新 ' + fmtFull(last) + '（' + hist.length + ' 点）' : '暂无数据'}
            </span>
            <Button size="small" onClick={onToggleSmooth}>
              {smooth ? '平滑' : '折线'}
            </Button>
          </Space>
        ),
      }}
      tabList={tabList}
      tabActiveKey={tab}
      onTabChange={setTab}
    >
      {body}
    </PageContainer>
  );
}
