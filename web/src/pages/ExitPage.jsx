// 出口页：一个出口拆成 IPv4 / IPv6 两张卡，各自有曲线、系列开关、时间轴和统计表。
// 合在一起看不清——v4 的 ICMP/HTTP 目标和 v6 的 DNS 目标量级差一截。
import { useMemo, useState } from 'react';
import { ProCard } from '@ant-design/pro-components';
import { Tag, Button, Space, Segmented } from 'antd';

const { CheckableTag } = Tag;
import LineChart from '../components/LineChart.jsx';
import TimeAxis, { PCT } from '../components/TimeAxis.jsx';
import StatTable from '../components/StatTable.jsx';
import { WINDOWS, fmtFull } from '../stats.js';
import { wantsV4, wantsV6, targetsFor } from '../api.js';

function Block({ cfg, hist, label, prefix, targets, range, onRangeChange, statWin, onPickWin, rangeCustom, smooth }) {
  const [hidden, setHidden] = useState(() => new Set());

  const span = useMemo(
    () => (hist.length ? { min: hist[0].ts * 1000, max: hist[hist.length - 1].ts * 1000 } : { min: 0, max: 0 }),
    [hist]
  );

  const winMs = range ? range.max - range.min : 0;
  const endTs = range ? range.max / 1000 : 0;

  // 时间轴把窗口归一化到 0..1000，两个把手的位置由当前 range 反推
  const lo = span.max > span.min ? ((range.min - span.min) / (span.max - span.min)) * PCT : 0;
  const hi = span.max > span.min ? ((range.max - span.min) / (span.max - span.min)) * PCT : PCT;

  const onAxis = (nlo, nhi) => {
    if (span.max <= span.min) return;
    const min = span.min + (nlo / PCT) * (span.max - span.min);
    const max = span.min + (nhi / PCT) * (span.max - span.min);
    onRangeChange({ min, max });
  };

  const allHidden = targets.length > 0 && targets.every((t) => hidden.has(t.name));

  return (
    <ProCard
      title={label}
      bordered
      style={{ marginBottom: 16 }}
      extra={
        <Space size={8}>
          <span className="lm-updated">● 实时</span>
          <Segmented
            size="small"
            value={winMs}
            onChange={(v) => onPickWin(v)}
            options={WINDOWS.map((w) => ({ label: w.label, value: w.ms }))}
          />
          <Button size="small" onClick={() => setHidden(allHidden ? new Set() : new Set(targets.map((t) => t.name)))}>
            {allHidden ? '全选' : '全不选'}
          </Button>
        </Space>
      }
    >
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
        {targets.map((t) => {
          const key = prefix + '|' + t.name;
          const last = hist.length ? hist[hist.length - 1].series[key] : null;
          const v = last && last.value !== null && last.value !== undefined ? Math.round(last.value) + 'ms' : '—';
          const on = !hidden.has(t.name);
          return (
            <CheckableTag
              key={t.name}
              checked={on}
              onChange={(next) => {
                const s = new Set(hidden);
                if (next) s.delete(t.name); else s.add(t.name);
                setHidden(s);
              }}
            >
              {t.grp ? <span style={{ color: 'rgba(255,255,255,.45)', marginRight: 4 }}>{t.grp}</span> : null}
              {t.name} <span style={{ color: 'rgba(255,255,255,.45)' }}>{v}</span>
            </CheckableTag>
          );
        })}
      </div>

      <LineChart
        hist={hist}
        targets={targets}
        prefix={prefix}
        hidden={hidden}
        smooth={smooth}
        range={range}
        onRangeChange={onRangeChange}
      />

      <TimeAxis
        lo={lo}
        hi={hi}
        onChange={onAxis}
        startLabel={span.max > span.min ? fmtFull(range.min / 1000) : '—'}
        endLabel={span.max > span.min ? fmtFull(range.max / 1000) : '—'}
        active={rangeCustom}
        onReset={() => onPickWin(0)}
      />

      <div className="lm-note">
        断线=该时刻失败（曲线断开，底部标红点）；虚线=本次采样部分丢包（ICMP 丢包 ≥10%），
        IPv6 曲线平时即虚线，丢包时换成更密的虚线。
      </div>

      <div style={{ marginTop: 24 }}>
        <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 12 }}>
          统计 · {label}
        </div>
        <StatTable
          hist={hist}
          groups={[{ label, prefix, targets }]}
          winMs={winMs}
          endTs={endTs}
          th={cfg.th || {}}
          showGroup={false}
        />
      </div>
    </ProCard>
  );
}

export default function ExitPage({ cfg, hist, exit, range, onRangeChange, statWin, onPickWin, rangeCustom, smooth }) {
  const lbl = exit.label || exit.if;
  // 出口可以声明只测哪几组目标（内网组网线路只测对端子网 IP，外网线路只测公网 DNS）。
  // 没声明就是全测，老配置行为不变。
  // targetsFor 每次调用都返回新数组，不稳住的话 LineChart 的数据 effect 会在
  // 每次重渲染（速率 2 秒一轮询）里白跑一遍 update，用户滚轮缩放到一半就被打断。
  const v4Targets = useMemo(() => targetsFor(exit, cfg.targets_v4), [exit, cfg]);
  const v6Targets = useMemo(() => targetsFor(exit, cfg.targets_v6), [exit, cfg]);
  return (
    <>
      {wantsV4(exit) ? (
        <Block
          cfg={cfg} hist={hist} label={`${lbl} · IPv4`} prefix={exit.if}
          targets={v4Targets} range={range} onRangeChange={onRangeChange}
          statWin={statWin} onPickWin={onPickWin} rangeCustom={rangeCustom} smooth={smooth}
        />
      ) : null}
      {wantsV6(exit) ? (
        <Block
          cfg={cfg} hist={hist} label={`${lbl} · IPv6`} prefix={'v6-' + exit.if}
          targets={v6Targets} range={range} onRangeChange={onRangeChange}
          statWin={statWin} onPickWin={onPickWin} rangeCustom={rangeCustom} smooth={smooth}
        />
      ) : null}
    </>
  );
}
