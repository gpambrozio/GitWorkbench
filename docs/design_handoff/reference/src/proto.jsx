// proto.jsx — Direction C "Workbench" as a fully interactive prototype.
// Real state: select files, stage/unstage (individual + bulk), edit commit message,
// commit, switch branch (dropdown), discard (with confirm), pull/push/fetch (with
// progress + toast), unified↔split diff toggle. Fills the viewport like a real app.

const { useState, useRef, useEffect, useCallback } = React;

// ── deep clone of mock data into mutable state ──────────────
function initialFiles() {
  return window.GITDATA.files.map((f) => ({ ...f }));
}

// ── tiny toast system ───────────────────────────────────────
function Toast({ toast }) {
  if (!toast) return null;
  return (
    <div style={{
      position: 'absolute', bottom: 26, left: '50%', transform: 'translateX(-50%)',
      background: 'rgba(34,34,40,0.94)', color: '#fff', borderRadius: 10, padding: '10px 16px',
      fontSize: 12.5, fontWeight: 500, fontFamily: GT.font, display: 'flex', alignItems: 'center', gap: 9,
      boxShadow: '0 8px 30px rgba(0,0,0,0.34)', zIndex: 60, backdropFilter: 'blur(20px)',
      animation: 'toastIn 0.22s ease',
    }}>
      {toast.spin
        ? <span className="gt-spin" style={{ width: 13, height: 13, borderRadius: '50%', border: '2px solid rgba(255,255,255,0.3)', borderTopColor: '#fff', display: 'inline-block' }} />
        : <Icon name={toast.icon || 'check'} size={14} color={toast.color || '#65d98a'} strokeWidth={2} />}
      {toast.msg}
    </div>
  );
}

// ── branch dropdown menu ────────────────────────────────────
function BranchMenu({ branches, current, ahead, behind, onPick, onClose }) {
  const ref = useRef(null);
  useEffect(() => {
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
    document.addEventListener('mousedown', h); return () => document.removeEventListener('mousedown', h);
  }, [onClose]);
  return (
    <div ref={ref} style={{
      position: 'absolute', top: 38, left: 0, width: 280, background: 'rgba(247,247,249,0.86)',
      backdropFilter: 'blur(30px) saturate(180%)', borderRadius: 11, padding: 6, zIndex: 50,
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.16), 0 16px 44px rgba(0,0,0,0.26)',
    }}>
      <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: GT.ink3, padding: '7px 10px 5px' }}>Switch branch</div>
      {branches.map((b) => {
        const on = b === current;
        return (
          <div key={b} onClick={() => onPick(b)} className="gt-menuitem" style={{
            display: 'flex', alignItems: 'center', gap: 9, padding: '7px 10px', borderRadius: 7, cursor: 'pointer',
          }}>
            <GitBranch size={14} color={on ? GT.accent : GT.ink3} />
            <span style={{ fontSize: 13, fontWeight: on ? 700 : 500, color: GT.ink, flex: 1 }}>{b}</span>
            {on && <span style={{ fontSize: 10.5, color: GT.ink3, fontVariantNumeric: 'tabular-nums' }}>{ahead}↑ {behind}↓</span>}
            {on && <Icon name="check" size={13} color={GT.accent} strokeWidth={2} />}
          </div>
        );
      })}
      <div style={{ height: 1, background: GT.sep, margin: '6px 8px' }} />
      <div className="gt-menuitem" style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '7px 10px', borderRadius: 7, cursor: 'pointer' }}>
        <Icon name="plus" size={14} color={GT.ink2} />
        <span style={{ fontSize: 13, color: GT.ink2 }}>New branch from HEAD…</span>
      </div>
    </div>
  );
}

// ── confirm popover for discard ─────────────────────────────
function ConfirmPop({ file, onCancel, onConfirm }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 55, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.18)' }}>
      <div style={{ width: 360, background: GT.winBg, borderRadius: 13, padding: '20px 20px 16px', boxShadow: '0 18px 50px rgba(0,0,0,0.3), 0 0 0 0.5px rgba(0,0,0,0.12)', textAlign: 'center' }}>
        <div style={{ width: 44, height: 44, borderRadius: '50%', background: GT.delBg, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 12px' }}>
          <Icon name="discard" size={22} color={GT.del} strokeWidth={1.6} />
        </div>
        <div style={{ fontSize: 15, fontWeight: 700, color: GT.ink }}>Discard changes in {file.name}?</div>
        <div style={{ fontSize: 12.5, color: GT.ink2, marginTop: 6, lineHeight: 1.5 }}>This will permanently discard {file.add + file.del} line change{file.add + file.del !== 1 ? 's' : ''}. You can't undo this.</div>
        <div style={{ display: 'flex', gap: 9, marginTop: 18 }}>
          <button onClick={onCancel} style={btn('ghost')}>Cancel</button>
          <button onClick={onConfirm} style={btn('danger')}>Discard Changes</button>
        </div>
      </div>
    </div>
  );
}

function btn(kind) {
  const base = { flex: 1, height: 34, border: 'none', borderRadius: 8, cursor: 'pointer', fontFamily: GT.font, fontSize: 13, fontWeight: 600 };
  if (kind === 'danger') return { ...base, background: GT.del, color: '#fff' };
  return { ...base, background: 'rgba(0,0,0,0.07)', color: GT.ink };
}

// ── interactive rail item ───────────────────────────────────
function RailItem({ icon, branch, label, count, selected, current, indent = 12, onClick }) {
  return (
    <div onClick={onClick} className="gt-rail" style={{
      display: 'flex', alignItems: 'center', gap: 8, height: 28, margin: '0 8px', padding: `0 8px 0 ${indent}px`,
      borderRadius: 6, cursor: 'pointer', background: selected ? GT.accent : 'transparent',
    }}>
      {branch ? <GitBranch size={13} color={selected ? '#fff' : (current ? GT.accent : GT.ink3)} /> : icon ? <Icon name={icon} size={13} color={selected ? '#fff' : GT.ink2} /> : null}
      <span style={{ fontSize: 12.5, fontWeight: current ? 700 : 500, color: selected ? '#fff' : GT.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{label}</span>
      {current && !selected && <span style={{ fontSize: 9, fontWeight: 700, color: GT.accent, background: GT.accentSoft, borderRadius: 4, padding: '1px 5px' }}>HEAD</span>}
      {count != null && <span style={{ fontSize: 11, fontWeight: 600, color: selected ? 'rgba(255,255,255,0.85)' : GT.ink3, fontVariantNumeric: 'tabular-nums' }}>{count}</span>}
    </div>
  );
}

function RailHeader({ title, action }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '14px 16px 5px' }}>
      <span style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase', color: GT.ink3, flex: 1 }}>{title}</span>
      {action}
    </div>
  );
}

// ── interactive file row ────────────────────────────────────
function FileRow({ file, selected, onSelect, onToggleStage, onDiscard }) {
  const [hover, setHover] = useState(false);
  return (
    <div onClick={onSelect} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 8, height: 30, padding: '0 12px', cursor: 'pointer', background: selected ? GT.accent : hover ? 'rgba(0,0,0,0.045)' : 'transparent' }}>
      <span onClick={(e) => { e.stopPropagation(); onToggleStage(); }} title={file.staged ? 'Unstage' : 'Stage'} style={{ display: 'flex', borderRadius: 4 }} className="gt-press">
        <StageBox checked={file.staged} size={15} />
      </span>
      <StatusGlyph status={file.status} size={15} filled={selected} />
      <span style={{ fontSize: 12.5, fontWeight: 500, color: selected ? '#fff' : GT.ink, whiteSpace: 'nowrap' }}>{file.name}</span>
      <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.7)' : GT.ink3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{file.dir}</span>
      {hover ? (
        <span onClick={(e) => { e.stopPropagation(); onDiscard(); }} title="Discard changes" className="gt-press" style={{ width: 20, height: 20, borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', background: selected ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.06)' }}>
          <Icon name="discard" size={12} color={selected ? '#fff' : GT.ink2} />
        </span>
      ) : (
        <StatChips add={file.add} del={file.del} size={11} />
      )}
    </div>
  );
}

function Group({ title, count, children, action }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '8px 12px 5px', background: GT.sidebar, position: 'sticky', top: 0, zIndex: 1 }}>
        <Icon name="chevDown" size={10} color={GT.ink3} strokeWidth={1.7} />
        <span style={{ fontSize: 11, fontWeight: 700, color: GT.ink2, textTransform: 'uppercase', letterSpacing: 0.3 }}>{title}</span>
        <span style={{ fontSize: 10.5, fontWeight: 600, color: GT.ink3, background: 'rgba(0,0,0,0.06)', borderRadius: 8, padding: '1px 6px' }}>{count}</span>
        <span style={{ flex: 1 }} />
        {action}
      </div>
      {children}
    </div>
  );
}

// ── interactive commit composer ─────────────────────────────
function Composer({ stagedCount, value, onChange, onCommit, branch }) {
  const ready = stagedCount > 0 && value.trim().length > 0;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <textarea value={value} onChange={(e) => onChange(e.target.value)} placeholder="Message (⌘↵ to commit)"
        onKeyDown={(e) => { if ((e.metaKey || e.ctrlKey) && e.key === 'Enter' && ready) onCommit(); }}
        style={{
          resize: 'none', height: 58, padding: '9px 11px', borderRadius: 8, border: 'none',
          background: GT.field, boxShadow: `inset 0 0 0 1px ${GT.sep}`, fontFamily: GT.font, fontSize: 13,
          color: GT.ink, outline: 'none', lineHeight: 1.45,
        }}
        onFocus={(e) => e.target.style.boxShadow = `inset 0 0 0 1.5px ${GT.accentRing}`}
        onBlur={(e) => e.target.style.boxShadow = `inset 0 0 0 1px ${GT.sep}`} />
      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={() => ready && onCommit()} disabled={!ready} style={{
          flex: 1, height: 30, border: 'none', borderRadius: 7, cursor: ready ? 'pointer' : 'default',
          background: ready ? GT.accent : 'rgba(0,0,0,0.07)', color: ready ? '#fff' : GT.ink3,
          fontFamily: GT.font, fontSize: 13, fontWeight: 600, boxShadow: ready ? '0 1px 2px rgba(124,92,224,0.4)' : 'none',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7, transition: 'background 0.15s',
        }}>
          <Icon name="check" size={13} color={ready ? '#fff' : GT.ink3} strokeWidth={1.8} />
          Commit {stagedCount ? `${stagedCount} file${stagedCount > 1 ? 's' : ''}` : ''} to {branch}
        </button>
      </div>
    </div>
  );
}

// ── main prototype ──────────────────────────────────────────
function Workbench() {
  const G = window.GITDATA;
  const { HistoryBody, StashBody } = window;
  const [files, setFiles] = useState(initialFiles);
  const [view, setView] = useState('changes'); // 'changes' | 'history' | 'stashes'
  const [sel, setSel] = useState('sync');
  const [mode, setMode] = useState('split');
  const [branch, setBranch] = useState(G.branch);
  const [ahead, setAhead] = useState(G.ahead);
  const [behind, setBehind] = useState(G.behind);
  const [msg, setMsg] = useState('Add retry/backoff to sync + watch command');
  const [menuOpen, setMenuOpen] = useState(false);
  const [confirm, setConfirm] = useState(null);
  const [toast, setToast] = useState(null);
  const [busy, setBusy] = useState(false);
  const toastTimer = useRef(null);

  const branches = ['main', 'develop', G.branch, 'fix/log-levels'];
  const staged = files.filter((f) => f.staged);
  const unstaged = files.filter((f) => !f.staged);
  const file = files.find((f) => f.id === sel);

  const flash = useCallback((t, ms = 2200) => {
    clearTimeout(toastTimer.current); setToast(t);
    toastTimer.current = setTimeout(() => setToast(null), ms);
  }, []);

  const toggleStage = (id) => setFiles((fs) => fs.map((f) => f.id === id ? { ...f, staged: !f.staged } : f));
  const stageAll = () => setFiles((fs) => fs.map((f) => ({ ...f, staged: true })));
  const unstageAll = () => setFiles((fs) => fs.map((f) => ({ ...f, staged: false })));

  const doDiscard = (f) => {
    setFiles((fs) => fs.filter((x) => x.id !== f.id));
    if (sel === f.id) setSel(null);
    setConfirm(null);
    flash({ msg: `Discarded changes in ${f.name}`, icon: 'discard', color: '#ff8a80' });
  };

  const doCommit = () => {
    const n = staged.length;
    const summary = msg.split('\n')[0];
    setFiles((fs) => fs.filter((f) => !f.staged));
    setAhead((a) => a + 1);
    setMsg('');
    setSel((cur) => (staged.find((f) => f.id === cur) ? null : cur));
    flash({ msg: `Committed ${n} file${n > 1 ? 's' : ''} · “${summary.length > 32 ? summary.slice(0, 32) + '…' : summary}”` });
  };

  const sync = (kind) => {
    if (busy) return;
    setBusy(true);
    flash({ msg: kind === 'pull' ? 'Pulling from origin…' : kind === 'push' ? 'Pushing to origin…' : 'Fetching…', spin: true }, 9000);
    setTimeout(() => {
      setBusy(false);
      if (kind === 'pull') { setBehind(0); flash({ msg: `Pulled ${behind} commit${behind !== 1 ? 's' : ''} from origin` }); }
      else if (kind === 'push') { setAhead(0); flash({ msg: `Pushed ${ahead} commit${ahead !== 1 ? 's' : ''} to origin` }); }
      else flash({ msg: 'Up to date with origin' });
    }, 1400);
  };

  const switchBranch = (b) => {
    setMenuOpen(false);
    if (b === branch) return;
    setBranch(b);
    flash({ msg: `Switched to ${b}`, icon: 'check' });
  };

  return (
    <Win width="100%" height="100%" style={{ borderRadius: 0, boxShadow: 'none' }}>
      {/* toolbar */}
      <div style={{ height: 52, flexShrink: 0, display: 'flex', alignItems: 'center', background: GT.titlebar, borderBottom: `1px solid ${GT.sep}`, position: 'relative', zIndex: 20 }}>
        <div style={{ width: 218, display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px 0 20px', flexShrink: 0, borderRight: `1px solid ${GT.sep}` }}>
          <TrafficLights />
          <span style={{ fontSize: 13, fontWeight: 700 }}>{G.repo}</span>
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 3, padding: '0 14px' }}>
          <span className="gt-press"><ToolBtn icon="arrowDown" label={`Pull${behind ? ' ' + behind : ''}`} onClick={() => sync('pull')} /></span>
          <span className="gt-press"><ToolBtn icon="arrowUp" label={`Push${ahead ? ' ' + ahead : ''}`} onClick={() => sync('push')} /></span>
          <span className="gt-press"><ToolBtn icon="sync" label="Fetch" onClick={() => sync('fetch')} /></span>
          <span style={{ width: 1, height: 22, background: GT.sep, margin: '0 6px' }} />
          <div style={{ position: 'relative' }}>
            <span className="gt-press" onClick={() => setMenuOpen((o) => !o)}><BranchPill name={branch} dim /></span>
            {menuOpen && <BranchMenu branches={branches} current={branch} ahead={ahead} behind={behind} onPick={switchBranch} onClose={() => setMenuOpen(false)} />}
          </div>
          <ToolBtn icon="history" label="History" active={view === 'history'} onClick={() => setView('history')} />
          <ToolBtn icon="folder" label="Stash" active={view === 'stashes'} onClick={() => setView('stashes')} />
          <span style={{ flex: 1 }} />
          <Segmented value={mode} onPick={setMode} options={[{ value: 'unified', icon: 'rows' }, { value: 'split', icon: 'columns' }]} />
        </div>
      </div>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {/* left rail */}
        <div style={{ width: 218, flexShrink: 0, background: GT.sidebarDeep, borderRight: `1px solid ${GT.sep}`, overflow: 'auto' }}>
          <RailHeader title="Workspace" />
          <RailItem icon="file" label="Changes" count={files.length} selected={view === 'changes'} onClick={() => setView('changes')} />
          <RailItem icon="history" label="History" count={G.commits.length} selected={view === 'history'} onClick={() => setView('history')} />
          <RailItem icon="folder" label="Stashes" count={G.stashes.length} selected={view === 'stashes'} onClick={() => setView('stashes')} />
          <RailHeader title="Branches" />
          {branches.map((b) => <RailItem key={b} branch label={b} current={b === branch} onClick={() => switchBranch(b)} />)}
          <RailHeader title="Remotes" />
          <RailItem icon="folder" label="origin" />
          <RailItem branch label={`origin/${branch}`} indent={26} />
        </div>

        {/* ── CHANGES view ── */}
        {view === 'changes' && <>
        {/* file list + commit */}
        <div style={{ width: 320, flexShrink: 0, background: GT.sidebar, borderRight: `1px solid ${GT.sep}`, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
          <div style={{ flex: 1, overflow: 'auto' }}>
            {staged.length > 0 && (
              <Group title="Staged" count={staged.length} action={<span onClick={unstageAll} className="gt-link" style={{ fontSize: 11, fontWeight: 600, color: GT.accentDeep, cursor: 'pointer' }}>Unstage all</span>}>
                {staged.map((f) => <FileRow key={f.id} file={f} selected={sel === f.id} onSelect={() => setSel(f.id)} onToggleStage={() => toggleStage(f.id)} onDiscard={() => setConfirm(f)} />)}
              </Group>
            )}
            {unstaged.length > 0 && (
              <Group title="Changes" count={unstaged.length} action={<span onClick={stageAll} className="gt-link" style={{ fontSize: 11, fontWeight: 600, color: GT.accentDeep, cursor: 'pointer' }}>Stage all</span>}>
                {unstaged.map((f) => <FileRow key={f.id} file={f} selected={sel === f.id} onSelect={() => setSel(f.id)} onToggleStage={() => toggleStage(f.id)} onDiscard={() => setConfirm(f)} />)}
              </Group>
            )}
            {files.length === 0 && (
              <div style={{ padding: '60px 24px', textAlign: 'center', color: GT.ink3 }}>
                <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(0,0,0,0.05)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 12px' }}>
                  <Icon name="check" size={22} color={GT.add} strokeWidth={1.8} />
                </div>
                <div style={{ fontSize: 13, fontWeight: 600, color: GT.ink2 }}>Working tree clean</div>
                <div style={{ fontSize: 12, marginTop: 4 }}>No changes to commit.</div>
              </div>
            )}
          </div>
          <div style={{ flexShrink: 0, borderTop: `1px solid ${GT.sep}`, padding: 12, background: GT.sidebar }}>
            <Composer stagedCount={staged.length} value={msg} onChange={setMsg} onCommit={doCommit} branch={branch} />
          </div>
        </div>

        {/* diff */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, background: GT.winBg, position: 'relative' }}>
          {file ? (
            <>
              <div style={{ height: 44, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 10, padding: '0 16px', borderBottom: `1px solid ${GT.sep}` }}>
                <FileMeta file={file} />
                <span style={{ width: 1, height: 18, background: GT.sep, margin: '0 6px' }} />
                <span style={{ fontSize: 11.5, color: GT.ink3, whiteSpace: 'nowrap' }}>{G.statusLabel[file.status]}</span>
                <span style={{ flex: 1 }} />
                <span className="gt-press"><ToolBtn icon={file.staged ? 'minus' : 'plus'} size={26} label={file.staged ? 'Unstage' : 'Stage'} onClick={() => toggleStage(file.id)} /></span>
                <span className="gt-press"><ToolBtn icon="discard" size={26} onClick={() => setConfirm(file)} /></span>
              </div>
              <div style={{ flex: 1, overflow: 'auto' }}><DiffView file={file} mode={mode} /></div>
            </>
          ) : <EmptyDiff label={files.length ? 'Select a file to view changes' : 'Nothing to show — working tree is clean'} />}
          {confirm && <ConfirmPop file={confirm} onCancel={() => setConfirm(null)} onConfirm={() => doDiscard(confirm)} />}
        </div>
        </>}

        {/* ── HISTORY view ── */}
        {view === 'history' && <HistoryBody mode={mode} flash={flash} />}

        {/* ── STASH view ── */}
        {view === 'stashes' && <StashBody mode={mode} flash={flash} />}
      </div>
      <Toast toast={toast} />
    </Win>
  );
}

Object.assign(window, { Workbench });
