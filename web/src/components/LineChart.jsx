// Chart.js 折线图的 React 外壳。
// 建图只做一次，之后原地换数据——重建会把用户的缩放窗口一起丢掉。
import { useEffect, useRef } from 'react';
import { Chart, buildLineDatasets, lineOptions, refreshLimits, dataSpan } from '../chart.js';

export default function LineChart({
  hist, targets, prefix, hidden, smooth, range, onRangeChange, height = 340,
}) {
  const canvasRef = useRef(null);
  const chartRef = useRef(null);
  const cbRef = useRef(onRangeChange);
  cbRef.current = onRangeChange;
  const histRef = useRef(hist);
  histRef.current = hist;
  const rangeRef = useRef(range);
  rangeRef.current = range;

  useEffect(() => {
    const span = dataSpan(hist);
    const { ds } = buildLineDatasets(hist, targets, prefix, hidden);
    const options = lineOptions({ span, smooth });
    // 滚轮/拖拽改完窗口要把新范围报回上层：底部的区间条和统计表都靠 range 反推，
    // 不上报的话把手会停在原地，看起来就是「缩了图表但条没动」。
    const report = ({ chart }) => {
      const x = chart.scales.x;
      const s = dataSpan(histRef.current);
      // 窗口已经盖满全量数据时归成「默认」，跟旧看板的 xRangeCustom 语义对齐
      const full = s.max > s.min && x.min <= s.min + 1000 && x.max >= s.max - 1000;
      cbRef.current?.({ min: x.min, max: x.max, full });
    };
    // 回调层级很容易写错，插件内部读的是 state.options.zoom.onZoomComplete 与
    // state.options.pan.onPanComplete，而 state.options 就是 plugins.zoom：
    //   wheel / 捏合 / 框选缩放 → plugins.zoom.zoom.onZoomComplete（三层）
    //   拖拽平移                → plugins.zoom.pan.onPanComplete（两层）
    // 缩放回调少写一层（plugins.zoom.onZoomComplete）插件不注册 handler，一路静默：
    // 时间条把手不动，而且每次重渲染图表都被 range 拉回旧窗口，看着就是
    // 「缩放后自动恢复默认」。pan 的结构不一样，别跟着一起改。
    options.plugins.zoom.zoom.onZoomComplete = report;
    options.plugins.zoom.pan.onPanComplete = report;

    const c = new Chart(canvasRef.current, {
      type: 'line',
      data: { datasets: ds },
      options,
    });
    chartRef.current = c;
    return () => {
      c.destroy();
      chartRef.current = null;
    };
    // 只在挂载时建一次
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 数据或显隐变化：原地替换数据集。窗口由 range 说了算（见下面的 effect），
  // 这里只把 range 贴回 options——chart.js 每次 update 都会按 options 里的
  // min/max 重新 fit，不贴回去的话轴会停在建图那一刻（实测数据涨到 04:02 而轴停在 03:52）。
  useEffect(() => {
    const c = chartRef.current;
    if (!c) return;
    const span = dataSpan(hist);
    const { ds } = buildLineDatasets(hist, targets, prefix, hidden);
    c.data.datasets = ds;
    // limits 要在 update 之前刷新，否则新采集的点会被旧边界挡在外面
    refreshLimits(c, span);
    const r = rangeRef.current;
    c.options.scales.x.min = r ? r.min : span.min;
    c.options.scales.x.max = r ? r.max : span.max;
    c.update('none');
    // range 走 ref：数据刷新这里不该触发缩放，免得和用户手势打架
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hist, targets, prefix, hidden]);

  // 平滑开关
  useEffect(() => {
    const c = chartRef.current;
    if (!c) return;
    c.data.datasets.forEach((d) => {
      d.tension = smooth ? 0.3 : 0;
    });
    c.update('none');
  }, [smooth]);

  // 窗口变化（预设按钮 / 时间轴滑块 / 滚轮缩放回报 / 新数据推进）。
  // 已经是这个范围就别再动了，不然会和用户正在拖的手势打架。
  useEffect(() => {
    const c = chartRef.current;
    if (!c || !range) return;
    c.options.scales.x.min = range.min;
    c.options.scales.x.max = range.max;
    const x = c.scales.x;
    if (Math.abs(x.min - range.min) < 1 && Math.abs(x.max - range.max) < 1) return;
    c.zoomScale('x', { min: range.min, max: range.max }, 'none');
  }, [range]);

  return (
    <div style={{ position: 'relative', height }}>
      <canvas ref={canvasRef} />
    </div>
  );
}
