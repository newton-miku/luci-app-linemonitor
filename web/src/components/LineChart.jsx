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

  useEffect(() => {
    const span = dataSpan(hist);
    const { ds } = buildLineDatasets(hist, targets, prefix, hidden);
    const options = lineOptions({ span, smooth });
    // 滚轮/拖拽改完窗口要把新范围报回上层，否则预设按钮的高亮状态会跟实际窗口对不上
    const report = ({ chart }) => {
      const x = chart.scales.x;
      cbRef.current?.({ min: x.min, max: x.max });
    };
    options.onZoomComplete = report;
    options.onPanComplete = report;

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

  // 数据或显隐变化：原地替换数据集
  useEffect(() => {
    const c = chartRef.current;
    if (!c) return;
    const span = dataSpan(hist);
    const { ds } = buildLineDatasets(hist, targets, prefix, hidden);
    c.data.datasets = ds;
    c.options.scales.x.min = span.min;
    c.options.scales.x.max = span.max;
    refreshLimits(c, span);
    c.update('none');
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

  // 外部改窗口（预设按钮 / 时间轴滑块）。已经是这个范围就别再动了，
  // 不然会和用户正在拖的手势打架。
  useEffect(() => {
    const c = chartRef.current;
    if (!c || !range) return;
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
