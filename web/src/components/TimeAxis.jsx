// 底部时间轴：一条轨道 + 两个把手，拖动只改 x 轴窗口，不改数据。
// 参考的是 antd pro 分析页那张折线图底部的 dataZoom 滑块——
// 就是「两端各一个竖条、中间一段高亮、下面写着起止时间」那个东西。
import { useRef } from 'react';

const PCT = 1000; // 把时间窗口归一化到 0..1000，避免用浮点当滑块值

export default function TimeAxis({ lo, hi, onChange, startLabel, endLabel, onReset, active }) {
  const trackRef = useRef(null);
  const dragRef = useRef(null);

  const pctFromEvent = (e) => {
    const el = trackRef.current;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    if (r.width <= 0) return null;
    const x = (e.clientX ?? 0) - r.left;
    return Math.max(0, Math.min(PCT, Math.round((x / r.width) * PCT)));
  };

  // 按下哪一段就拖哪一段：左边把手改 lo、右边把手改 hi、中间那段整体平移。
  const onDown = (which) => (e) => {
    dragRef.current = {
      which,
      startX: e.clientX,
      lo0: lo,
      hi0: hi,
      // 中间段要先算出「按下点相对 lo 的偏移」，平移时才不会跳
      grabOffset: which === 'sel' ? (pctFromEvent(e) ?? 0) - lo : 0,
    };
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };

  const onMove = (e) => {
    const d = dragRef.current;
    if (!d) return;
    const el = trackRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    if (r.width <= 0) return;
    const cur = pctFromEvent(e);
    if (cur === null) return;
    const MIN = 4; // 两个把手最少隔 0.4%，免得贴死后拖不回来

    if (d.which === 'lo') {
      onChange(Math.max(0, Math.min(cur, hi - MIN)), hi);
    } else if (d.which === 'hi') {
      onChange(lo, Math.min(PCT, Math.max(cur, lo + MIN)));
    } else {
      const width = d.hi0 - d.lo0;
      let nl = cur - d.grabOffset;
      nl = Math.max(0, Math.min(PCT - width, nl));
      onChange(nl, nl + width);
    }
  };

  const onUp = (e) => {
    dragRef.current = null;
    e.currentTarget.releasePointerCapture?.(e.pointerId);
  };

  const widthPct = ((hi - lo) / PCT) * 100;

  return (
    <div className="lm-timeaxis" style={{ position: 'relative', height: 38, margin: '2px 10px 0' }}>
      {active && onReset ? (
        <span
          onClick={onReset}
          style={{
            position: 'absolute', right: 0, top: -16, fontSize: 11,
            color: '#1668dc', cursor: 'pointer', userSelect: 'none',
          }}
        >
          重置窗口
        </span>
      ) : null}

      <div ref={trackRef} style={{ position: 'absolute', inset: 0 }}>
        <div style={{
          position: 'absolute', left: 0, right: 0, top: 14, height: 4,
          background: '#303030', borderRadius: 2,
        }} />
        <div
          onPointerDown={onDown('sel')}
          onPointerMove={onMove}
          onPointerUp={onUp}
          style={{
            position: 'absolute', left: `${(lo / PCT) * 100}%`, width: `${widthPct}%`,
            top: 14, height: 4, background: '#1668dc', borderRadius: 2,
            cursor: 'grab', touchAction: 'none',
          }}
        />
        {['lo', 'hi'].map((which) => {
          const pos = which === 'lo' ? lo : hi;
          return (
            <div
              key={which}
              onPointerDown={onDown(which)}
              onPointerMove={onMove}
              onPointerUp={onUp}
              style={{
                position: 'absolute',
                left: `calc(${(pos / PCT) * 100}% - 4.5px)`,
                top: 4, width: 9, height: 24, borderRadius: 3,
                background: '#1668dc', border: '1px solid #0b3a63',
                boxShadow: '0 0 0 2px rgba(22,104,220,.16)',
                cursor: 'col-resize', touchAction: 'none',
              }}
            />
          );
        })}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          display: 'flex', justifyContent: 'space-between',
          fontSize: 11, color: 'rgba(255,255,255,.45)', userSelect: 'none',
        }}>
          <span>{startLabel}</span>
          <span>{endLabel}</span>
        </div>
      </div>
    </div>
  );
}

export { PCT };
