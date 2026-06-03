// diff.jsx — shared diff rendering + git-specific bits.
// Exports: StatusGlyph, StatChips, StageBox, FileMeta, DiffView, CommitComposer, EmptyDiff, HunkHeader

function StatusGlyph({ status, size = 16, filled = false }) {
  const map = { M: GT.mod, A: GT.add, D: GT.del, R: GT.ren, U: GT.unt };
  const c = map[status] || GT.ink3;
  return (
    <span style={{
      width: size, height: size, borderRadius: 4, flexShrink: 0,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: GT.mono, fontSize: size * 0.62, fontWeight: 700, lineHeight: 1,
      color: filled ? '#fff' : c,
      background: filled ? c : 'transparent',
      boxShadow: filled ? 'none' : `inset 0 0 0 1.25px ${c}`,
    }}>{status}</span>
  );
}

function StatChips({ add, del, gap = 8, size = 12 }) {
  return (
    <span style={{ display: 'inline-flex', gap, fontFamily: GT.mono, fontSize: size, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
      {add > 0 && <span style={{ color: GT.addInk }}>+{add}</span>}
      {del > 0 && <span style={{ color: GT.delInk }}>−{del}</span>}
    </span>
  );
}

// Tiny checkbox used for stage / unstage
function StageBox({ checked, partial = false, size = 16 }) {
  return (
    <span style={{
      width: size, height: size, borderRadius: 4, flexShrink: 0,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      background: checked ? GT.accent : '#fff',
      boxShadow: checked ? 'none' : `inset 0 0 0 1.25px ${GT.sepStrong}`,
    }}>
      {checked && !partial && <Icon name="check" size={size * 0.72} color="#fff" strokeWidth={1.8} />}
      {partial && <span style={{ width: size * 0.5, height: 2, borderRadius: 1, background: '#fff' }} />}
    </span>
  );
}

// Filename + dimmed path + stats — used in diff headers and detail panes
function FileMeta({ file, showPath = true, big = false }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 9, minWidth: 0 }}>
      <StatusGlyph status={file.status} size={big ? 18 : 16} />
      <span style={{ display: 'flex', alignItems: 'baseline', gap: 7, minWidth: 0 }}>
        <span style={{ fontSize: big ? 15 : 13, fontWeight: 600, color: GT.ink, whiteSpace: 'nowrap' }}>{file.name}</span>
        {showPath && file.dir && (
          <span style={{ fontSize: big ? 12.5 : 11.5, color: GT.ink3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{file.dir}/</span>
        )}
      </span>
      <span style={{ flex: 1 }} />
      <StatChips add={file.add} del={file.del} size={big ? 13 : 12} />
    </div>
  );
}

function HunkHeader({ text }) {
  return (
    <div style={{
      fontFamily: GT.mono, fontSize: 11.5, color: GT.ink3, padding: '5px 14px',
      background: 'rgba(124,92,224,0.05)', borderTop: `1px solid ${GT.sep}`, borderBottom: `1px solid ${GT.sep}`,
      whiteSpace: 'pre',
    }}>{text}</div>
  );
}

// ── Unified diff ────────────────────────────────────────────
function gutCell(no, w = 46) {
  return <span style={{ width: w, flexShrink: 0, textAlign: 'right', paddingRight: 12, color: GT.ink3, userSelect: 'none' }}>{no ?? ''}</span>;
}

function UnifiedRow({ line }) {
  const bg = line.t === 'add' ? GT.addBg : line.t === 'del' ? GT.delBg : 'transparent';
  const sign = line.t === 'add' ? '+' : line.t === 'del' ? '−' : ' ';
  const signColor = line.t === 'add' ? GT.addInk : line.t === 'del' ? GT.delInk : GT.ink3;
  const bar = line.t === 'add' ? GT.addGut : line.t === 'del' ? GT.delGut : 'transparent';
  return (
    <div style={{ display: 'flex', background: bg, boxShadow: `inset 3px 0 0 ${bar}` }}>
      {gutCell(line.o)}{gutCell(line.n)}
      <span style={{ width: 20, flexShrink: 0, textAlign: 'center', color: signColor, fontWeight: 700, userSelect: 'none' }}>{sign}</span>
      <span style={{ flex: 1, whiteSpace: 'pre', paddingRight: 16, color: GT.ink }}>{line.text || ' '}</span>
    </div>
  );
}

function DiffUnified({ file }) {
  return (
    <div style={{ fontFamily: GT.mono, fontSize: 12, lineHeight: '20px' }}>
      {file.hunks.map((h, i) => (
        <div key={i}>
          <HunkHeader text={h.header} />
          {h.lines.map((l, j) => <UnifiedRow key={j} line={l} />)}
        </div>
      ))}
    </div>
  );
}

// ── Split diff ──────────────────────────────────────────────
function splitRows(lines) {
  const rows = []; let dels = [], adds = [];
  const flush = () => {
    const m = Math.max(dels.length, adds.length);
    for (let i = 0; i < m; i++) rows.push({ left: dels[i] || null, right: adds[i] || null });
    dels = []; adds = [];
  };
  for (const l of lines) {
    if (l.t === 'ctx') { flush(); rows.push({ left: l, right: l }); }
    else if (l.t === 'del') dels.push(l);
    else adds.push(l);
  }
  flush();
  return rows;
}

function SplitSide({ cell, side }) {
  const empty = !cell;
  const isChange = cell && cell.t !== 'ctx';
  const bg = !cell ? 'rgba(0,0,0,0.025)' : cell.t === 'add' ? GT.addBg : cell.t === 'del' ? GT.delBg : 'transparent';
  const no = side === 'left' ? (cell && cell.o) : (cell && cell.n);
  const sign = isChange ? (cell.t === 'add' ? '+' : '−') : '';
  const signColor = cell && cell.t === 'add' ? GT.addInk : GT.delInk;
  return (
    <div style={{ flex: 1, minWidth: 0, display: 'flex', background: bg, borderRight: side === 'left' ? `1px solid ${GT.sep}` : 'none' }}>
      <span style={{ width: 40, flexShrink: 0, textAlign: 'right', paddingRight: 10, color: GT.ink3, userSelect: 'none' }}>{no ?? ''}</span>
      <span style={{ width: 14, flexShrink: 0, textAlign: 'center', color: signColor, fontWeight: 700, userSelect: 'none' }}>{sign}</span>
      <span style={{ flex: 1, whiteSpace: 'pre', overflow: 'hidden', textOverflow: 'ellipsis', paddingRight: 10, color: empty ? 'transparent' : GT.ink }}>{cell ? (cell.text || ' ') : ''}</span>
    </div>
  );
}

function DiffSplit({ file }) {
  return (
    <div style={{ fontFamily: GT.mono, fontSize: 12, lineHeight: '20px' }}>
      {file.hunks.map((h, i) => (
        <div key={i}>
          <HunkHeader text={h.header} />
          {splitRows(h.lines).map((r, j) => (
            <div key={j} style={{ display: 'flex' }}>
              <SplitSide cell={r.left} side="left" />
              <SplitSide cell={r.right} side="right" />
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function DiffView({ file, mode = 'unified' }) {
  if (!file) return <EmptyDiff />;
  if (file.status === 'D') {
    return (
      <div style={{ fontFamily: GT.mono, fontSize: 12, lineHeight: '20px', opacity: 0.92 }}>
        {file.hunks.map((h, i) => (
          <div key={i}>{h.lines.map((l, j) => <UnifiedRow key={j} line={l} />)}</div>
        ))}
      </div>
    );
  }
  return mode === 'split' ? <DiffSplit file={file} /> : <DiffUnified file={file} />;
}

function EmptyDiff({ label = 'Select a file to view changes' }) {
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12, color: GT.ink3 }}>
      <div style={{ width: 46, height: 46, borderRadius: 12, background: 'rgba(0,0,0,0.05)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="file" size={22} color={GT.ink3} />
      </div>
      <span style={{ fontSize: 13 }}>{label}</span>
    </div>
  );
}

// ── Commit composer ─────────────────────────────────────────
function CommitComposer({ stagedCount = 0, placeholder = 'Message (⌘↵ to commit)', compact = false, message = '', branch }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{
        background: GT.field, borderRadius: 8, boxShadow: `inset 0 0 0 1px ${GT.sep}`,
        padding: compact ? '8px 10px' : '10px 12px', minHeight: compact ? 34 : 58,
      }}>
        <div style={{ fontSize: 13, color: message ? GT.ink : GT.ink3, lineHeight: 1.45, whiteSpace: 'pre-wrap' }}>{message || placeholder}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <button style={{
          flex: 1, height: 30, border: 'none', borderRadius: 7, cursor: 'pointer',
          background: stagedCount ? GT.accent : 'rgba(0,0,0,0.07)',
          color: stagedCount ? '#fff' : GT.ink3, fontFamily: GT.font, fontSize: 13, fontWeight: 600,
          boxShadow: stagedCount ? '0 1px 2px rgba(124,92,224,0.4)' : 'none',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
        }}>
          <Icon name="check" size={13} color={stagedCount ? '#fff' : GT.ink3} strokeWidth={1.8} />
          Commit {stagedCount ? `${stagedCount} file${stagedCount > 1 ? 's' : ''}` : ''}{branch ? ` to ${branch}` : ''}
        </button>
        <button style={{
          width: 30, height: 30, border: 'none', borderRadius: 7, cursor: 'pointer',
          background: 'rgba(0,0,0,0.07)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icon name="chevDown" size={13} color={GT.ink2} />
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { StatusGlyph, StatChips, StageBox, FileMeta, HunkHeader, DiffView, DiffUnified, DiffSplit, EmptyDiff, CommitComposer });
