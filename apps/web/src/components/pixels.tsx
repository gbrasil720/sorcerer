/** A bar of █ and ░ like the app's meters; ember when `warn`. */
export function Meter({
  value,
  cells = 14,
  warn,
}: {
  value: number;
  cells?: number;
  warn?: boolean;
}) {
  const on = Math.round(Math.max(0, Math.min(1, value)) * cells);
  return (
    <span className="inline-flex h-3 overflow-hidden" aria-hidden>
      <span
        className={`h-full transition-[width] duration-700 ${warn ? "bg-ember" : "bg-paper"}`}
        style={{ width: on * 7 }}
      />
      <span
        className="h-full bg-[length:4px_4px] bg-[repeating-conic-gradient(var(--color-dim)_0_25%,transparent_0_50%)] transition-[width] duration-700"
        style={{ width: (cells - on) * 7 }}
      />
    </span>
  );
}

export const signed = (m: number) =>
  m === 0 ? "±0.0" : `${m > 0 ? "+" : "−"}${Math.abs(m).toFixed(1)}`;

/* ---------- pixel art ---------- */

// Traced from the brand artboard; same bitmap as Pixels.hat in the macOS app.
export const HAT = [
  ".o............",
  "owo......##...",
  ".o......##g...",
  ".......###g...",
  "......##o#g...",
  "......####g...",
  ".....#o####g..",
  ".....######g..",
  "....#######g..",
  "....oooooooO..",
  "...#########g.",
  "#############g",
  ".ddddddddddd..",
];
const PIXEL_COLORS: Record<string, string> = {
  "#": "var(--color-paper)",
  w: "#fff8ee",
  o: "var(--color-ember)",
  O: "#b5532d",
  g: "#8c8983",
  d: "#6e6b66",
};

export function Pixels({
  rows,
  size,
  gap = 0,
  className,
}: {
  rows: string[];
  size: number;
  /** Fraction of a pixel left empty, for the block-letter look. */
  gap?: number;
  className?: string;
}) {
  const w = rows[0].length;
  return (
    <svg
      className={className}
      width={w * size}
      height={rows.length * size}
      viewBox={`0 0 ${w} ${rows.length}`}
      shapeRendering="crispEdges"
      aria-hidden
    >
      {rows.flatMap((row, y) =>
        [...row].map((c, x) =>
          c === "." ? null : (
            <rect
              key={`${x}-${y}`}
              x={x}
              y={y}
              width={1 - gap}
              height={1 - gap}
              fill={PIXEL_COLORS[c]}
            />
          ),
        ),
      )}
    </svg>
  );
}
/* Deterministic 16×16 portrait per handle; same algorithm and palettes as Avatar in the macOS app. */
const AV = {
  hairs: ["#1e1a17", "#5a3a22", "#c08a4a", "#e6d27a", "#d9d6cf", "#f0773a"],
  skins: ["#f4d9c0", "#e2b48c", "#c48a62", "#9a6440", "#6b4429"],
  outfits: ["#2a2724", "#f0773a", "#3f6b5c", "#3b4a8c", "#7a3346", "#e9e6df"],
  bgs: ["#3a2a1f", "#23221f", "#1c2733", "#1f2a20", "#2a1f2a"],
  accents: ["#f0773a", "#e9e6df", "#6f7fe0", "#4fa37d", "#e0c24a"],
};

function fnv(s: string) {
  let h = 2166136261;
  for (const c of new TextEncoder().encode(s))
    h = Math.imul(h ^ c, 16777619) >>> 0;
  return h;
}

export function Avatar({
  name,
  size = 16,
  className = "",
}: {
  name: string;
  size?: number;
  className?: string;
}) {
  const h = fnv(name);
  const at = (shift: number, mod: number) => (h >>> shift) % mod;
  const style = h % 5; // short, long, bun, buzz, curly
  const hair = AV.hairs[at(3, 6)];
  const skin = AV.skins[at(6, 5)];
  const outfit = AV.outfits[at(9, 6)];
  const bg = AV.bgs[at(12, 5)];
  const accent = AV.accents[at(15, 5)];
  const glasses = at(18, 3) === 0;
  const beanie = !glasses && at(20, 4) === 0;
  const headphones = !beanie && at(22, 6) === 0;
  const beard = at(24, 5) === 0;
  const earring = at(26, 5) === 0;
  const scarf = !beard && at(28, 6) === 0;
  const dark = "#1a1714";

  const px: [number, number, string, number][] = [];
  const p = (x: number, y: number, c: string, o = 1) => px.push([x, y, c, o]);
  const row = (y: number, a: number, b: number, c: string, o = 1) => {
    for (let x = a; x <= b; x++) p(x, y, c, o);
  };

  for (let y = 0; y < 16; y++)
    for (let x = 0; x < 16; x++)
      if ((((x >> 1) + (y >> 1)) & 1) === 0) p(x, y, "#fff", 0.04);
  if (style === 1)
    for (let y = 4; y <= 11; y++) {
      row(y, 2, 3, hair);
      row(y, 12, 13, hair);
    }
  if (style === 4)
    for (let y = 3; y <= 8; y++) {
      row(y, 2, 3, hair);
      row(y, 12, 13, hair);
    }
  for (let y = 4; y <= 9; y++) row(y, 4, 11, skin);
  row(10, 5, 10, skin);
  row(11, 7, 8, skin);
  if (style === 0 || style === 2 || style === 3) {
    p(3, 7, skin);
    p(12, 7, skin);
  }
  if (style === 3) row(3, 4, 11, hair);
  else if (style === 4) {
    row(1, 4, 11, hair);
    row(2, 3, 12, hair);
    row(3, 3, 12, hair);
    for (let x = 4; x <= 11; x += 2) p(x, 1, hair, 0.75);
  } else {
    row(2, 4, 11, hair);
    row(3, 3, 12, hair);
    p(3, 4, hair);
    p(12, 4, hair);
    if (style === 2) {
      row(0, 6, 9, hair);
      row(1, 7, 8, hair);
    }
  }
  row(6, 5, 6, hair, 0.9);
  row(6, 9, 10, hair, 0.9);
  p(6, 7, dark);
  p(9, 7, dark);
  p(4, 8, "#e89a8a");
  p(11, 8, "#e89a8a");
  row(9, 7, 8, "#7a3b2a");
  row(12, 5, 10, outfit);
  for (let y = 13; y <= 15; y++) row(y, 3, 12, outfit);
  p(7, 12, skin);
  p(8, 12, skin);
  if (beard) {
    row(9, 4, 6, hair);
    row(9, 9, 11, hair);
    row(10, 5, 10, hair);
  }
  if (glasses) {
    row(7, 4, 11, dark);
    row(8, 5, 6, dark);
    row(8, 9, 10, dark);
  }
  if (beanie) {
    row(1, 4, 11, accent);
    row(2, 3, 12, accent);
    row(3, 3, 12, accent, 0.85);
    for (let x = 4; x <= 12; x += 2) p(x, 2, accent, 0.7);
    row(0, 7, 8, accent);
  }
  if (headphones) {
    row(2, 3, 12, accent);
    for (let y = 6; y <= 8; y++) {
      row(y, 2, 3, accent);
      row(y, 12, 13, accent);
    }
  }
  if (earring) p(3, 9, accent);
  if (scarf) {
    row(11, 4, 11, accent);
    row(12, 4, 11, accent);
  }

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      shapeRendering="crispEdges"
      aria-hidden
      className={`shrink-0 rounded-[3px] ${className}`}
    >
      <rect width={16} height={16} fill={bg} />
      {px.map(([x, y, c, o], i) => (
        <rect
          key={i}
          x={x}
          y={y}
          width={1}
          height={1}
          fill={c}
          fillOpacity={o}
        />
      ))}
    </svg>
  );
}
