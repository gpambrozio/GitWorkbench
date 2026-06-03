// proto-views.jsx — History and Stash bodies for the Workbench prototype.
// Each renders the middle list pane + right detail pane (the rail stays in Workbench).
// Exports to window: HistoryBody, StashBody
const { useState: useStateV } = React;

// ── shared: selectable changed-file row in a detail pane ────
function DetailFileRow({ file, selected, onSelect }) {
  return (
    <div onClick={onSelect} style={{
      display: 'flex', alignItems: 'center', gap: 9, height: 30, padding: '0 16px', cursor: 'pointer',
      background: selected ? GT.accentSoft : 'transparent', boxShadow: selected ? `inset 2px 0 0 ${GT.accent}` : 'none',
    }}>
      <StatusGlyph status={file.status} size={15} />
      <span style={{ fontSize: 12.5, fontWeight: 500, color: GT.ink, whiteSpace: 'nowrap' }}>{file.name}</span>
      <span style={{ fontSize: 11, color: GT.ink3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{file.dir}</span>
      <StatChips add={file.add} del={file.del} size={11} />
    </div>
  );
}

function TagPill({ label }) {
  const isHead = label === 'HEAD';
  const isVer = /^v?\d/.test(label);
  const color = isHead ? GT.accent : isVer ? GT.add : GT.ren;
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 9.5, fontWeight: 700, color, background: `${color}1f`, borderRadius: 4, padding: '1px 5px', whiteSpace: 'nowrap' }}>
      {isVer ? <Icon name="tag" size={9} color={color} strokeWidth={1.6} /> : isHead ? null : <GitBranch size={9} color={color} />}
      {label}
    </span>
  );
}

// ════════════════════════ HISTORY ════════════════════════
function CommitRow({ commit, selected, first, last, onSelect }) {
  return (
    <div onClick={onSelect} className={selected ? '' : 'gt-commitrow'} style={{
      display: 'flex', cursor: 'pointer', background: selected ? GT.accent : 'transparent',
    }}>
      {/* graph */}
      <div style={{ width: 34, flexShrink: 0, position: 'relative' }}>
        <div style={{ position: 'absolute', left: 16, top: 0, bottom: 0, width: 2, background: selected ? 'rgba(255,255,255,0.35)' : GT.sepStrong, ...(first ? { top: '50%' } : {}), ...(last ? { bottom: '50%' } : {}) }} />
        <div style={{ position: 'absolute', left: 11, top: 'calc(50% - 5px)', width: 10, height: 10, borderRadius: '50%', background: selected ? '#fff' : GT.winBg, boxShadow: `0 0 0 2px ${selected ? '#fff' : GT.accent}` }} />
      </div>
      <div style={{ flex: 1, minWidth: 0, padding: '9px 14px 9px 2px', borderBottom: `1px solid ${selected ? 'transparent' : GT.sep2}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontSize: 12.5, fontWeight: 600, color: selected ? '#fff' : GT.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{commit.summary}</span>
          {commit.tags.map((t) => selected ? <span key={t} style={{ fontSize: 9.5, fontWeight: 700, color: '#fff', background: 'rgba(255,255,255,0.22)', borderRadius: 4, padding: '1px 5px', whiteSpace: 'nowrap' }}>{t}</span> : <TagPill key={t} label={t} />)}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 5 }}>
          <Avatar initials={commit.initials} size={15} hue={commit.initials === 'GA' ? 295 : 25} />
          <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.85)' : GT.ink2, whiteSpace: 'nowrap' }}>{commit.author}</span>
          <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.7)' : GT.ink3 }}>· {commit.relative}</span>
          <span style={{ flex: 1 }} />
          <span style={{ fontFamily: GT.mono, fontSize: 10.5, color: selected ? 'rgba(255,255,255,0.8)' : GT.ink3 }}>{commit.short}</span>
        </div>
      </div>
    </div>
  );
}

function HistoryBody({ mode, flash }) {
  const G = window.GITDATA;
  const [selSha, setSelSha] = useStateV(G.commits[0].sha);
  const commit = G.commits.find((c) => c.sha === selSha);
  const [selFile, setSelFile] = useStateV(commit.files[0].id);
  const file = commit.files.find((f) => f.id === selFile) || commit.files[0];

  const pick = (c) => { setSelSha(c.sha); setSelFile(c.files[0].id); };

  return (
    <>
      {/* commit list */}
      <div style={{ width: 360, flexShrink: 0, background: GT.sidebar, borderRight: `1px solid ${GT.sep}`, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '10px 14px', borderBottom: `1px solid ${GT.sep}` }}>
          <Icon name="history" size={13} color={GT.ink2} />
          <span style={{ fontSize: 11, fontWeight: 700, color: GT.ink2, textTransform: 'uppercase', letterSpacing: 0.3 }}>History</span>
          <span style={{ fontSize: 10.5, fontWeight: 600, color: GT.ink3, background: 'rgba(0,0,0,0.06)', borderRadius: 8, padding: '1px 6px' }}>{G.commits.length}</span>
          <span style={{ flex: 1 }} />
          <BranchPill name={G.branch} dim style={{ height: 24, fontSize: 11.5 }} />
        </div>
        <div style={{ flex: 1, overflow: 'auto' }}>
          {G.commits.map((c, i) => <CommitRow key={c.sha} commit={c} selected={selSha === c.sha} first={i === 0} last={i === G.commits.length - 1} onSelect={() => pick(c)} />)}
        </div>
      </div>

      {/* commit detail */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', background: GT.winBg }}>
        <div style={{ padding: '16px 20px 14px', borderBottom: `1px solid ${GT.sep}` }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: GT.ink, letterSpacing: -0.2 }}>{commit.summary}</div>
          {commit.body && <div style={{ fontSize: 12.5, color: GT.ink2, marginTop: 7, lineHeight: 1.55, whiteSpace: 'pre-wrap', fontFamily: GT.mono }}>{commit.body}</div>}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 14 }}>
            <Avatar initials={commit.initials} size={26} hue={commit.initials === 'GA' ? 295 : 25} />
            <div style={{ lineHeight: 1.25 }}>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: GT.ink }}>{commit.author} <span style={{ color: GT.ink3, fontWeight: 400 }}>&lt;{commit.email}&gt;</span></div>
              <div style={{ fontSize: 11.5, color: GT.ink3 }}>committed {commit.date}</div>
            </div>
            <span style={{ flex: 1 }} />
            <button onClick={() => flash && flash({ msg: `Copied ${commit.short} to clipboard` })} className="gt-press" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 26, padding: '0 10px', border: 'none', borderRadius: 7, background: 'rgba(0,0,0,0.06)', cursor: 'pointer', fontFamily: GT.mono, fontSize: 11.5, fontWeight: 600, color: GT.ink2 }}>
              <Icon name="copy" size={12} color={GT.ink2} /> {commit.short}
            </button>
          </div>
        </div>
        <div style={{ flexShrink: 0, borderBottom: `1px solid ${GT.sep}`, background: '#fafafb', paddingTop: 6 }}>
          <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: GT.ink3, padding: '4px 16px 6px' }}>
            {commit.files.length} changed file{commit.files.length > 1 ? 's' : ''}
          </div>
          <div style={{ paddingBottom: 6 }}>
            {commit.files.map((f) => <DetailFileRow key={f.id} file={f} selected={selFile === f.id} onSelect={() => setSelFile(f.id)} />)}
          </div>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }}><DiffView file={file} mode={mode} /></div>
      </div>
    </>
  );
}

// ════════════════════════ STASH ════════════════════════
function StashRow({ stash, selected, onSelect }) {
  return (
    <div onClick={onSelect} className={selected ? '' : 'gt-commitrow'} style={{
      display: 'flex', flexDirection: 'column', gap: 5, padding: '11px 14px', cursor: 'pointer',
      background: selected ? GT.accent : 'transparent', borderBottom: `1px solid ${selected ? 'transparent' : GT.sep2}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ fontFamily: GT.mono, fontSize: 10.5, fontWeight: 700, color: selected ? '#fff' : GT.accentDeep, background: selected ? 'rgba(255,255,255,0.2)' : GT.accentSoft, borderRadius: 4, padding: '1px 6px' }}>{stash.ref}</span>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: selected ? '#fff' : GT.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{stash.message}</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <GitBranch size={11} color={selected ? 'rgba(255,255,255,0.8)' : GT.ink3} />
        <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.85)' : GT.ink2 }}>{stash.branch}</span>
        <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.7)' : GT.ink3 }}>· {stash.relative}</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: selected ? 'rgba(255,255,255,0.7)' : GT.ink3 }}>{stash.files.length} file{stash.files.length > 1 ? 's' : ''}</span>
      </div>
    </div>
  );
}

function StashAction({ icon, label, primary, danger, onClick }) {
  return (
    <button onClick={onClick} className="gt-press" style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, height: 28, padding: '0 12px', borderRadius: 7, border: 'none', cursor: 'pointer',
      fontFamily: GT.font, fontSize: 12.5, fontWeight: 600,
      background: primary ? GT.accent : danger ? GT.delBg : 'rgba(0,0,0,0.06)',
      color: primary ? '#fff' : danger ? GT.del : GT.ink2,
      boxShadow: primary ? '0 1px 2px rgba(124,92,224,0.4)' : 'none',
    }}>
      <Icon name={icon} size={13} color={primary ? '#fff' : danger ? GT.del : GT.ink2} /> {label}
    </button>
  );
}

function StashBody({ mode, flash }) {
  const G = window.GITDATA;
  const [list, setList] = useStateV(G.stashes);
  const [selId, setSelId] = useStateV(G.stashes[0] ? G.stashes[0].id : null);
  const stash = list.find((s) => s.id === selId);
  const [selFile, setSelFile] = useStateV(stash ? stash.files[0].id : null);
  const file = stash && (stash.files.find((f) => f.id === selFile) || stash.files[0]);

  const pick = (s) => { setSelId(s.id); setSelFile(s.files[0].id); };
  const remove = (id, verb) => {
    const s = list.find((x) => x.id === id);
    const next = list.filter((x) => x.id !== id);
    setList(next);
    if (selId === id) { const n = next[0]; setSelId(n ? n.id : null); setSelFile(n ? n.files[0].id : null); }
    flash && flash({ msg: `${verb} ${s.ref} — “${s.message}”` });
  };
  const apply = (s) => flash && flash({ msg: `Applied ${s.ref} to working tree` });

  return (
    <>
      {/* stash list */}
      <div style={{ width: 360, flexShrink: 0, background: GT.sidebar, borderRight: `1px solid ${GT.sep}`, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '10px 14px', borderBottom: `1px solid ${GT.sep}` }}>
          <Icon name="folder" size={13} color={GT.ink2} />
          <span style={{ fontSize: 11, fontWeight: 700, color: GT.ink2, textTransform: 'uppercase', letterSpacing: 0.3 }}>Stashes</span>
          <span style={{ fontSize: 10.5, fontWeight: 600, color: GT.ink3, background: 'rgba(0,0,0,0.06)', borderRadius: 8, padding: '1px 6px' }}>{list.length}</span>
          <span style={{ flex: 1 }} />
          <span className="gt-press" title="Stash current changes"><ToolBtn icon="plus" size={24} label="Stash" /></span>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }}>
          {list.length ? list.map((s) => <StashRow key={s.id} stash={s} selected={selId === s.id} onSelect={() => pick(s)} />)
            : <div style={{ padding: '60px 24px', textAlign: 'center', color: GT.ink3 }}>
                <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(0,0,0,0.05)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 12px' }}><Icon name="folder" size={22} color={GT.ink3} /></div>
                <div style={{ fontSize: 13, fontWeight: 600, color: GT.ink2 }}>No stashes</div>
                <div style={{ fontSize: 12, marginTop: 4 }}>Shelved changes show up here.</div>
              </div>}
        </div>
      </div>

      {/* stash detail */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', background: GT.winBg }}>
        {stash ? (
          <>
            <div style={{ padding: '16px 20px 14px', borderBottom: `1px solid ${GT.sep}` }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                <span style={{ fontFamily: GT.mono, fontSize: 11.5, fontWeight: 700, color: GT.accentDeep, background: GT.accentSoft, borderRadius: 5, padding: '2px 7px' }}>{stash.ref}</span>
                <span style={{ fontSize: 16, fontWeight: 700, color: GT.ink, letterSpacing: -0.2 }}>{stash.message}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 10 }}>
                <GitBranch size={12} color={GT.ink3} />
                <span style={{ fontSize: 12, color: GT.ink2 }}>on {stash.branch}</span>
                <span style={{ fontSize: 12, color: GT.ink3 }}>· stashed {stash.date}</span>
                <span style={{ flex: 1 }} />
                <StashAction icon="tray" label="Apply" onClick={() => apply(stash)} />
                <StashAction icon="arrowUp" label="Pop" primary onClick={() => remove(stash.id, 'Popped')} />
                <StashAction icon="trash" label="Drop" danger onClick={() => remove(stash.id, 'Dropped')} />
              </div>
            </div>
            <div style={{ flexShrink: 0, borderBottom: `1px solid ${GT.sep}`, background: '#fafafb', paddingTop: 6 }}>
              <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: GT.ink3, padding: '4px 16px 6px' }}>{stash.files.length} changed file{stash.files.length > 1 ? 's' : ''}</div>
              <div style={{ paddingBottom: 6 }}>
                {stash.files.map((f) => <DetailFileRow key={f.id} file={f} selected={selFile === f.id} onSelect={() => setSelFile(f.id)} />)}
              </div>
            </div>
            <div style={{ flex: 1, overflow: 'auto' }}><DiffView file={file} mode={mode} /></div>
          </>
        ) : <EmptyDiff label="No stash selected" />}
      </div>
    </>
  );
}

Object.assign(window, { HistoryBody, StashBody });
