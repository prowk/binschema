function betterInterval(left, right) {
  if (!left) return right;
  if (!right) return left;
  const leftLength = left.end - left.start;
  const rightLength = right.end - right.start;
  if (leftLength !== rightLength) return leftLength < rightLength ? left : right;
  return left.index < right.index ? left : right;
}

function prefixBest(intervals) {
  const result = [];
  let best = null;
  for (const interval of intervals) {
    best = betterInterval(best, interval);
    result.push(best);
  }
  return result;
}

function buildIntervalNode(intervals) {
  if (intervals.length === 0) return null;
  const starts = intervals.map((interval) => interval.start).sort((left, right) => left - right);
  const center = starts[Math.floor(starts.length / 2)];
  const left = [];
  const right = [];
  const crossing = [];

  for (const interval of intervals) {
    if (interval.end <= center) left.push(interval);
    else if (interval.start > center) right.push(interval);
    else crossing.push(interval);
  }

  const byStart = crossing.slice().sort((a, b) => a.start - b.start || a.index - b.index);
  const byEnd = crossing.slice().sort((a, b) => b.end - a.end || a.index - b.index);
  return {
    center,
    byStart,
    byStartBest: prefixBest(byStart),
    byEnd,
    byEndBest: prefixBest(byEnd),
    left: buildIntervalNode(left),
    right: buildIntervalNode(right),
  };
}

function lastStartAtMost(intervals, point) {
  let low = 0;
  let high = intervals.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (intervals[middle].start <= point) low = middle + 1;
    else high = middle;
  }
  return low - 1;
}

function lastEndAfter(intervals, point) {
  let low = 0;
  let high = intervals.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (intervals[middle].end > point) low = middle + 1;
    else high = middle;
  }
  return low - 1;
}

function queryIntervalNode(node, point) {
  if (!node) return null;
  if (point < node.center) {
    const position = lastStartAtMost(node.byStart, point);
    const crossing = position >= 0 ? node.byStartBest[position] : null;
    return betterInterval(crossing, queryIntervalNode(node.left, point));
  }
  const position = lastEndAfter(node.byEnd, point);
  const crossing = position >= 0 ? node.byEndBest[position] : null;
  return betterInterval(crossing, queryIntervalNode(node.right, point));
}

export class TraceIntervalIndex {
  constructor(entries) {
    const intervals = entries
      .map((entry, index) => ({ start: entry.start, end: entry.end, index }))
      .filter((entry) => Number.isInteger(entry.start) && Number.isInteger(entry.end) && entry.start >= 0 && entry.end > entry.start);
    this.root = buildIntervalNode(intervals);
  }

  find(byteIndex) {
    if (!Number.isInteger(byteIndex) || byteIndex < 0) return -1;
    return queryIntervalNode(this.root, byteIndex)?.index ?? -1;
  }
}

export function calculateHexWindow({
  byteLength,
  bytesPerRow,
  scrollTop,
  viewportHeight,
  rowHeight,
  overscanRows = 8,
}) {
  const safeLength = Math.max(0, Math.trunc(byteLength));
  const safeColumns = Math.max(1, Math.trunc(bytesPerRow));
  const safeRowHeight = Math.max(1, rowHeight);
  const totalRows = Math.ceil(safeLength / safeColumns);
  const firstVisibleRow = Math.max(0, Math.min(totalRows, Math.floor(Math.max(0, scrollTop) / safeRowHeight)));
  const visibleRows = Math.max(1, Math.ceil(Math.max(0, viewportHeight) / safeRowHeight));
  const overscan = Math.max(0, Math.trunc(overscanRows));
  const startRow = Math.max(0, firstVisibleRow - overscan);
  const endRow = Math.min(totalRows, firstVisibleRow + visibleRows + overscan);

  return {
    totalRows,
    startRow,
    endRow,
    startByte: startRow * safeColumns,
    endByte: Math.min(safeLength, endRow * safeColumns),
    topHeight: startRow * safeRowHeight,
    bottomHeight: (totalRows - endRow) * safeRowHeight,
  };
}
