// base.jsx — native macOS chrome primitives + design tokens for the git viewer.
// Exports to window: GT, Icon, TrafficLights, Win, ToolBtn, BranchPill, Segmented, Avatar
// Plain, flexible window chrome (no baked sidebar) so each direction composes freely.

const GT = {
  font: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif',
  mono: 'ui-monospace, "SF Mono", "Menlo", "Monaco", monospace',
  // surfaces
  winBg: '#ffffff',
  sidebar: '#f3f3f5',
  sidebarDeep: '#ebebee',
  titlebar: '#ececef',
  field: '#ffffff',
  // text
  ink: '#1d1d1f',
  ink2: '#62626a',
  ink3: '#8e8e96',
  // lines
  sep: 'rgba(0,0,0,0.09)',
  sepStrong: 'rgba(0,0,0,0.14)',
  // accent (purple) — oklch(~0.58 0.17 295)
  accent: '#7c5ce0',
  accentDeep: '#6a49d4',
  accentSoft: 'rgba(124,92,224,0.13)',
  accentRing: 'rgba(124,92,224,0.45)',
  // git status
  mod: '#c8852c',
  add: '#2e9e5b',
  del: '#d1453b',
  ren: '#2a6fdb',
  unt: '#8a8f98',
  // diff tints
  addBg: 'rgba(46,158,91,0.12)',
  addGut: 'rgba(46,158,91,0.20)',
  delBg: 'rgba(209,69,59,0.10)',
  delGut: 'rgba(209,69,59,0.18)',
  addInk: '#1c7a44',
  delInk: '#b23a30',
};

// ── Simple line icons (12–16px) ─────────────────────────────
const PATHS = {
  chevDown: 'M3 5.5L7 9.5L11 5.5',
  chevRight: 'M5.5 3L9.5 7L5.5 11',
  chevUpDown: 'M4 6L7 3L10 6 M4 8L7 11L10 8',
  plus: 'M7 2.5V11.5 M2.5 7H11.5',
  minus: 'M2.5 7H11.5',
  check: 'M2.5 7.5L5.5 10.5L11.5 3.5',
  dot: '',
  search: 'M6 1.5a4.5 4.5 0 100 9 4.5 4.5 0 000-9z M9.5 9.5l3 3',
  refresh: 'M11.5 3.5a5 5 0 10.8 5 M11.5 1.5v3h-3',
  arrowUp: 'M7 11.5V3 M3 6.5L7 2.5L11 6.5',
  arrowDown: 'M7 2.5V11 M3 7.5L7 11.5L11 7.5',
  sync: 'M2.5 7a4.5 4.5 0 017.7-3.2L12 5 M11.5 7a4.5 4.5 0 01-7.7 3.2L2 9 M12 2v3H9 M2 12V9h3',
  ellipsis: 'M3 7h.01 M7 7h.01 M11 7h.01',
  discard: 'M3 7a4 4 0 104-4 M3 4v3h3 M9.5 9.5l1.5 1.5 M11 9.5L9.5 11',
  history: 'M7 3.5v4l2.5 1.5 M7 1.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11z',
  columns: 'M2 2.5h10v9H2z M7 2.5v9',
  rows: 'M2 2.5h10v9H2z M2 7h10',
  file: 'M3.5 1.5h4l3 3v8h-7z M7.5 1.5v3h3',
  folder: 'M1.5 3.5h3.5l1 1.5h5v6h-9.5z',
  stage: 'M7 2.5v6 M4 5.5L7 2.5l3 3 M2.5 11.5h9',
  tag: 'M6.8 1.5H2.2v4.6L8 11.9 12.5 7.4 6.8 1.5z M4.3 4.3h.01',
  trash: 'M2.5 3.5h9 M5.4 3.5V2.4h3.2v1.1 M3.6 3.5l.5 8h5.8l.5-8',
  copy: 'M4.8 4.8h6.4v6.4H4.8z M2.8 9.2V2.8h6.4',
  tray: 'M2.5 8.5v3h9v-3 M7 1.8v5.7 M4.5 5.2L7 7.7l2.5-2.5',
};

function Icon({ name, size = 14, color = 'currentColor', strokeWidth = 1.4, style = {} }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none"
      stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"
      style={{ display: 'block', flexShrink: 0, ...style }}>
      <path d={PATHS[name] || ''} />
    </svg>
  );
}

// Git branch glyph (two nodes + connector) — small, hand-tuned
function GitBranch({ size = 14, color = 'currentColor', style = {} }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none" stroke={color}
      strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" style={{ display: 'block', flexShrink: 0, ...style }}>
      <circle cx="3.5" cy="3" r="1.4" /><circle cx="3.5" cy="11" r="1.4" /><circle cx="10.5" cy="4.5" r="1.4" />
      <path d="M3.5 4.4v5.2 M10.5 6v.5c0 2-2 2.5-4 3" />
    </svg>
  );
}

// ── Traffic lights ──────────────────────────────────────────
function TrafficLights({ size = 12, gap = 8 }) {
  const dot = (bg) => <span style={{ width: size, height: size, borderRadius: '50%', background: bg, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.12)' }} />;
  return <div style={{ display: 'flex', gap, alignItems: 'center' }}>{dot('#fc625d')}{dot('#fdbc40')}{dot('#34c84a')}</div>;
}

// ── Window frame (no chrome baked in — caller composes titlebar/body) ──
function Win({ width = 1180, height = 760, children, style = {} }) {
  return (
    <div style={{
      width, height, borderRadius: 11, overflow: 'hidden', background: GT.winBg,
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.28), 0 28px 70px rgba(0,0,0,0.34)',
      display: 'flex', flexDirection: 'column', fontFamily: GT.font, color: GT.ink,
      position: 'relative', ...style,
    }}>{children}</div>
  );
}

// ── Toolbar icon button ─────────────────────────────────────
function ToolBtn({ icon, label, size = 28, active = false, accent = false, dim = false, children, style = {}, onClick }) {
  return (
    <button onClick={onClick} style={{
      height: size, minWidth: label ? 'auto' : size, padding: label ? '0 10px' : 0,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
      borderRadius: 7, border: 'none', cursor: 'pointer', fontFamily: GT.font,
      fontSize: 12.5, fontWeight: 500, lineHeight: 1,
      color: accent ? '#fff' : (dim ? GT.ink3 : GT.ink2),
      background: accent ? GT.accent : (active ? 'rgba(0,0,0,0.08)' : 'transparent'),
      boxShadow: accent ? '0 1px 2px rgba(124,92,224,0.4)' : 'none',
      ...style,
    }}>
      {icon && <Icon name={icon} size={14} color={accent ? '#fff' : (dim ? GT.ink3 : GT.ink2)} />}
      {children}
      {label && <span>{label}</span>}
    </button>
  );
}

// ── Branch switcher pill ────────────────────────────────────
function BranchPill({ name = 'main', style = {}, dim = false }) {
  return (
    <button style={{
      height: 28, padding: '0 9px', display: 'inline-flex', alignItems: 'center', gap: 6,
      borderRadius: 7, border: 'none', cursor: 'pointer', background: dim ? 'transparent' : 'rgba(0,0,0,0.05)',
      fontFamily: GT.font, fontSize: 12.5, fontWeight: 600, color: GT.ink, ...style,
    }}>
      <GitBranch size={13} color={GT.accent} />
      <span style={{ maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
      <Icon name="chevUpDown" size={11} color={GT.ink3} strokeWidth={1.3} />
    </button>
  );
}

// ── Segmented control (unified / split toggle etc.) ─────────
function Segmented({ options, value, size = 26, onPick }) {
  return (
    <div style={{ display: 'inline-flex', padding: 2, gap: 2, background: 'rgba(0,0,0,0.06)', borderRadius: 8 }}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <div key={o.value} onClick={() => onPick && onPick(o.value)} style={{
            height: size, padding: o.label ? '0 11px' : `0 9px`, display: 'inline-flex', alignItems: 'center', gap: 5,
            borderRadius: 6, cursor: 'pointer', fontSize: 12, fontWeight: 600,
            color: on ? GT.ink : GT.ink2,
            background: on ? '#fff' : 'transparent',
            boxShadow: on ? '0 1px 2px rgba(0,0,0,0.14)' : 'none',
          }}>
            {o.icon && <Icon name={o.icon} size={13} color={on ? GT.ink : GT.ink2} />}
            {o.label && <span>{o.label}</span>}
          </div>
        );
      })}
    </div>
  );
}

// ── Author avatar (monogram disc) ───────────────────────────
function Avatar({ initials = 'GA', size = 24, hue = 295 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', flexShrink: 0,
      background: `oklch(0.62 0.15 ${hue})`, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.42, fontWeight: 600, letterSpacing: 0.2,
      boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.1)',
    }}>{initials}</div>
  );
}

Object.assign(window, { GT, Icon, GitBranch, TrafficLights, Win, ToolBtn, BranchPill, Segmented, Avatar });
