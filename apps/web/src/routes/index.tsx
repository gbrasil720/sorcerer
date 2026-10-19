import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";

export const Route = createFileRoute("/")({
  component: Landing,
});

// Placeholders kept from the design until the repo is public.
const REPO = "gbrasil720/sorcerer";
const GITHUB_URL = `https://github.com/${REPO}`;
// Always the newest release: the release workflow uploads Sorcerer.dmg to each one.
const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Sorcerer.dmg`;
const DOCS_URL = `${GITHUB_URL}#readme`;
const INSTALL_URL = `${GITHUB_URL}#install`;
const CHANGELOG_URL = `${GITHUB_URL}/releases`;

/** Live star count from GitHub; null until it loads (or if the API is unreachable). */
function useStars() {
  const [stars, setStars] = useState<number | null>(null);
  useEffect(() => {
    fetch(`https://api.github.com/repos/${REPO}`)
      .then((r) => (r.ok ? r.json() : null))
      .then(
        (d) =>
          typeof d?.stargazers_count === "number" &&
          setStars(d.stargazers_count),
      )
      .catch(() => {});
  }, []);
  return stars;
}
const LICENSE = "MIT";

export function Landing() {
  return (
    <div
      id="top"
      className="min-h-svh bg-ink font-display text-paper antialiased selection:bg-ember selection:text-ink"
    >
      <Nav />
      <main>
        <div className="mx-auto max-w-[1248px] px-6">
          <Hero />
        </div>
        <Ticker />
        <div className="mx-auto max-w-[1248px] px-6">
          <HowItWorks />
          <Demo />
          <Branching />
          <Spellbook />
          <LocalFirst />
          <FinalCta />
        </div>
      </main>
      <Footer />
    </div>
  );
}

/* ---------- shared bits ---------- */

function Eyebrow({ n, children }: { n: string; children: string }) {
  return (
    <p className="font-mono text-ember text-xs">
      — {n} / {children}
    </p>
  );
}

function Btn({
  href,
  primary,
  children,
}: {
  href: string;
  primary?: boolean;
  children: React.ReactNode;
}) {
  return (
    <a
      href={href}
      className={`inline-flex h-12 items-center border px-5 font-mono text-sm transition-colors ${
        primary
          ? "border-ember bg-ember text-ink hover:bg-ember/90"
          : "border-line text-paper hover:border-paper/40"
      }`}
    >
      {children}
    </a>
  );
}

const Panel = ({
  className = "",
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) => (
  <div className={`scanlines border border-line bg-panel ${className}`}>
    {children}
  </div>
);

/* ---------- pixel art ---------- */

// Traced from the brand artboard; same bitmap as Pixels.hat in the macOS app.
const HAT = [
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

const LETTERS: Record<string, string[]> = {
  S: [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
  O: [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
  R: ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
  C: [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
  E: ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
};

const PIXEL_COLORS: Record<string, string> = {
  "#": "var(--color-paper)",
  w: "#fff8ee",
  o: "var(--color-ember)",
  O: "#b5532d",
  g: "#8c8983",
  d: "#6e6b66",
};

function Pixels({
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

function Wordmark() {
  return (
    <div className="flex justify-center gap-3" role="img" aria-label="Sorcerer">
      {[..."SORCERER"].map((l, i) => (
        <Pixels
          key={i}
          rows={i === 7 ? ["###o.", ...LETTERS[l].slice(1)] : LETTERS[l]}
          size={9}
          gap={0.16}
          className="max-sm:h-10 max-sm:w-auto"
        />
      ))}
    </div>
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

function Avatar({
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

/* ---------- nav ---------- */

function Nav() {
  const links = [
    ["how it works", "#how"],
    ["demo", "#demo"],
    ["features", "#features"],
    ["local-first", "#local"],
    ["docs", DOCS_URL],
  ];
  const stars = useStars();
  return (
    <header className="sticky top-0 z-20 border-line border-b bg-ink/85 backdrop-blur">
      <nav className="mx-auto flex h-[78px] max-w-[1248px] items-center justify-between px-6">
        <a href="#top" className="flex items-center gap-3">
          <Pixels rows={HAT} size={2.3} />
          <span className="font-mono font-semibold">sorcerer</span>
          <span className="font-mono text-muted text-xs max-sm:hidden">
            v0.1 · open source
          </span>
        </a>
        <div className="flex items-center gap-6 font-mono text-muted text-sm">
          {links.map(([label, href]) => (
            <a
              key={href}
              href={href}
              className="hover:text-paper max-lg:hidden"
            >
              {label}
            </a>
          ))}
          <a
            href={GITHUB_URL}
            className="border border-line px-4 py-2.5 text-paper hover:border-paper/40"
          >
            ★ star{stars === null ? " on GitHub" : ` · ${stars}`}
          </a>
        </div>
      </nav>
    </header>
  );
}

/* ---------- hero ---------- */

function Hero() {
  return (
    <section className="grid items-center gap-14 py-20 lg:grid-cols-2 lg:py-24">
      <div>
        <p className="font-mono text-muted text-xs">
          [ open source ] · [ native app ] · [ local-first ] · [ bring your own
          AI ]
        </p>
        <h1 className="mt-6 font-medium text-6xl leading-[0.98] tracking-tight sm:text-7xl">
          Create a community.
          <br />
          Explore a hypothesis.
          <br />
          <span className="text-ember">Watch what happens.</span>
        </h1>
        <p className="mt-7 max-w-[520px] text-lg text-paper/80 leading-relaxed">
          Sorcerer brings small digital worlds to life. Summon agents with
          personalities, goals, relationships and memory, drop in a “what if…?”,
          and watch opinions form, collide and spread — round by round.
        </p>
        <div className="mt-7 flex flex-wrap gap-3">
          <Btn href={DOWNLOAD_URL} primary>
            ↓ download for macOS
          </Btn>
          <Btn href={GITHUB_URL}>★ star on GitHub</Btn>
          <Btn href={DOCS_URL}>read the docs →</Btn>
        </div>
        <p className="mt-7 font-mono text-muted text-xs">
          free · macOS 15+ · Apple silicon &amp; Intel —{" "}
          <a href={INSTALL_URL} className="text-paper underline">
            first launch?
          </a>{" "}
          — runs on your machine, with your AI subscriptions
        </p>
      </div>
      <World />
    </section>
  );
}

const AGENTS = ["ada", "bruno", "chen", "dara", "eli", "fumi", "gus", "iris"];
const QUOTES = [
  "source?",
  "saw it too",
  "not for notes",
  "need a reason",
  "cash grab?",
  "wait and see",
  "debunk it",
  "muted",
  "sharing now",
];
const HYPOTHESIS = "the rumor spreads on day one?";

const usePrefersReducedMotion = () =>
  useMemo(
    () =>
      typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    [],
  );

function World() {
  const reduced = usePrefersReducedMotion();
  const stars = useMemo(
    () =>
      Array.from({ length: 70 }, () => [
        Math.random() * 100,
        Math.random() * 100,
        Math.random(),
      ]),
    [],
  );
  const [tick, setTick] = useState(0);
  const [pos, setPos] = useState(() =>
    AGENTS.map((_, i) => [
      10 + (i % 4) * 22 + Math.random() * 6,
      12 + Math.floor(i / 4) * 55 + Math.random() * 10,
    ]),
  );
  const [said, setSaid] = useState<Record<number, string>>({});

  useEffect(() => {
    if (reduced) return;
    const id = setInterval(() => setTick((t) => t + 1), 900);
    return () => clearInterval(id);
  }, [reduced]);

  useEffect(() => {
    if (!tick) return;
    setPos((p) =>
      p.map(([x, y]) => [
        Math.min(85, Math.max(4, x + (Math.random() - 0.5) * 8)),
        Math.min(85, Math.max(4, y + (Math.random() - 0.5) * 8)),
      ]),
    );
    // after the hypothesis is typed, opinions start spreading
    if (tick % 40 > HYPOTHESIS.length / 3) {
      setSaid((s) => {
        const next = { ...s };
        const who = Math.floor(Math.random() * AGENTS.length);
        next[who] = QUOTES[Math.floor(Math.random() * QUOTES.length)];
        if (Object.keys(next).length > 4)
          delete next[Number(Object.keys(next)[0])];
        return next;
      });
    } else setSaid({});
  }, [tick]);

  const typed = HYPOTHESIS.slice(
    0,
    Math.min(HYPOTHESIS.length, (tick % 40) * 3),
  );

  return (
    <Panel className="font-mono text-xs">
      <div
        role="img"
        aria-label="Animated ASCII world: agents wander, a hypothesis is typed, a ripple spreads and agents react"
      >
        <div className="flex justify-between border-line border-b px-4 py-3 text-muted">
          <span>~/worlds/village.sim</span>
          <span>
            round{" "}
            <span className="text-paper">{14 + Math.floor(tick / 3)}</span> · 8
            agents · <span className="text-ember">● live</span>
          </span>
        </div>
        <div className="relative h-[324px] overflow-hidden">
          {stars.map(([x, y, s]) => (
            <span
              key={`${x}-${y}`}
              className="absolute text-dim"
              style={{ left: `${x}%`, top: `${y}%` }}
            >
              {s > 0.85 ? "*" : s > 0.5 ? "·" : "."}
            </span>
          ))}
          {typed === HYPOTHESIS && !reduced && (
            <span
              key={Math.floor(tick / 40)}
              className="ripple absolute top-1/2 left-1/2 size-4 rounded-full border border-ember"
            />
          )}
          {AGENTS.map((name, i) => (
            <div
              key={name}
              className="absolute transition-all duration-700 ease-linear"
              style={{ left: `${pos[i][0]}%`, top: `${pos[i][1]}%` }}
            >
              {said[i] && (
                <p className="absolute -top-5 whitespace-nowrap text-paper">
                  "{said[i]}"
                </p>
              )}
              <span className="flex items-center gap-2">
                <Avatar
                  name={name}
                  size={16}
                  className={
                    said[i] ? "outline outline-1 outline-ember" : "opacity-80"
                  }
                />
                <span className={said[i] ? "text-paper" : "text-paper/70"}>
                  {name}
                </span>
              </span>
            </div>
          ))}
        </div>
        <p className="border-line border-t px-4 py-3">
          <span className="text-ember">›</span>{" "}
          <span className="text-muted">what if</span>{" "}
          {reduced ? HYPOTHESIS : typed}
          <span className="animate-pulse text-ember">▍</span>
        </p>
      </div>
    </Panel>
  );
}

/* ---------- ticker ---------- */

const EVENTS = [
  "chen changed her mind",
  "rumor reached 6 of 8",
  "fork saved: branch B",
  "eli disagrees with fumi",
  "event injected: offline mode",
  "report updated",
  "paused: usage at 90%",
  "resumed",
  "dara replied to ada",
];

function Ticker() {
  const line = EVENTS.join("  ✦  ");
  return (
    <div
      className="overflow-hidden border-line border-y py-3 font-mono text-muted text-xs"
      aria-hidden
    >
      <div className="marquee flex w-max gap-6 whitespace-nowrap">
        <span>{line} ✦</span>
        <span>{line} ✦</span>
      </div>
    </div>
  );
}

/* ---------- 01 how it works ---------- */

function HowItWorks() {
  const steps = [
    {
      title: "Summon a community",
      body: "Create characters with personalities, interests, goals, relationships and their own memories. Seed the world with your texts and documents.",
      art: (
        <div className="relative h-full">
          {["ada", "bruno", "chen", "dara"].map((n, i) => (
            <span
              key={n}
              className="absolute"
              style={{ left: [8, 70, 132, 44][i], top: [12, 0, 12, 46][i] }}
            >
              <Avatar
                name={n}
                size={22}
                className={i === 3 ? "outline outline-1 outline-ember" : ""}
              />
            </span>
          ))}
          <span className="absolute top-3 left-9 text-muted">·····</span>
          <span className="absolute top-12 left-[76px] text-muted">·····</span>
        </div>
      ),
    },
    {
      title: "Cast a hypothesis",
      body: "Start with “What if…?”. Introduce a product, a price, a rumor or a rule, and let it ripple through the community.",
      art: (
        <div className="relative h-full">
          <pre className="absolute left-14 text-ember">
            {"~~~~~~~\n~  ✦  ~\n~~~~~~~"}
          </pre>
          {["eli", "fumi", "gus", "iris"].map((n, i) => (
            <span
              key={n}
              className="absolute opacity-70"
              style={{ left: [0, 170, 0, 170][i], top: [0, 0, 52, 52][i] }}
            >
              <Avatar name={n} size={18} />
            </span>
          ))}
        </div>
      ),
    },
    {
      title: "Observe and branch",
      body: "Follow the rounds, talk to characters, inject events — then save a moment and fork it to compare how each path evolves.",
      art: (
        <pre className="text-muted">
          <span className="text-ember">●──●</span>──●──● A{"\n"}
          {"   └─"}
          <span className="text-ember">●──● B</span>
        </pre>
      ),
    },
  ];
  return (
    <section id="how" className="scroll-mt-24 py-24">
      <Eyebrow n="01">how it works</Eyebrow>
      <h2 className="mt-4 font-medium text-5xl tracking-tight">
        It starts with a question.
      </h2>
      <p className="mt-4 max-w-[700px] text-lg text-paper/80">
        Describe a hypothesis, give the world some context, and populate it.
        Everything after that is observation — and a little bit of meddling.
      </p>
      <div className="mt-12 grid gap-4 md:grid-cols-3">
        {steps.map((s, i) => (
          <div key={s.title} className="border border-line bg-panel p-7">
            <div className="h-20 font-mono text-xs leading-5">{s.art}</div>
            <p className="mt-6 font-mono text-muted text-xs">0{i + 1}</p>
            <h3 className="mt-3 font-medium text-2xl">{s.title}</h3>
            <p className="mt-4 text-paper/75 leading-relaxed">{s.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ---------- 02 demo ---------- */

const CHARACTERS = [
  { name: "ada", role: "freelance designer · frugal", mood: -0.4 },
  { name: "bruno", role: "power user · wants speed", mood: 0.8 },
  { name: "chen", role: "student · price-sensitive", mood: -0.2 },
  { name: "dara", role: "team lead · owns the budget", mood: 0.2 },
  { name: "eli", role: "tech writer · skeptical", mood: -0.3 },
  { name: "fumi", role: "early adopter · loyal", mood: 0.6 },
];

const POSTS = [
  {
    who: "ada",
    meta: "posted r1",
    text: "$14 a month for notes? I'll wait and see what actually changes.",
  },
  { who: "bruno", meta: "posted r1", text: "If sync gets faster, I'd pay it." },
  {
    who: "chen",
    meta: "posted r2",
    text: "Is there a student plan? That's the real question.",
  },
  {
    who: "dara",
    meta: "replied to @ada r2",
    text: "For a team of eight that's $40 more a month. I need a reason to sign off.",
  },
  {
    who: "eli",
    meta: "posted r3",
    text: "A price hike with no new features reads as a cash grab.",
  },
  {
    who: "fumi",
    meta: "replied to @eli r3",
    text: "Annual at $120 would soften this a lot.",
  },
];

function MoodBar({ mood }: { mood: number }) {
  const filled = Math.round(((mood + 1) / 2) * 12);
  return (
    <span className={mood < 0 ? "text-ember" : "text-paper"}>
      [{"█".repeat(filled)}
      <span className="text-dim">{"░".repeat(12 - filled)}</span>]
    </span>
  );
}

function Demo() {
  return (
    <section id="demo" className="scroll-mt-24 py-24">
      <div className="flex flex-wrap items-end justify-between gap-6">
        <div>
          <Eyebrow n="02">a simulation, live</Eyebrow>
          <h2 className="mt-4 max-w-[640px] font-medium text-5xl tracking-tight">
            Watch every post, reply and change of heart.
          </h2>
          <p className="mt-4 max-w-[640px] text-lg text-paper/80">
            Rounds play out in the open. Pause anytime, inject an event, or pull
            a character aside to ask what they really think.
          </p>
        </div>
        <p className="max-w-[260px] font-mono text-muted text-xs leading-5">
          example scenario · fictional app “Lumen” raises its plan from $9 to
          $14 a month
        </p>
      </div>

      <Panel className="mt-10 font-mono text-xs">
        <div className="flex flex-wrap items-center justify-between gap-3 border-line border-b px-4 py-3">
          <span>
            lumen-pricing.sim <span className="text-muted">branch</span>{" "}
            <span className="text-ember">B · $14</span>{" "}
            <span className="text-muted">round</span> 4{" "}
            <span className="text-ember">● running</span>
          </span>
          <span className="flex gap-2">
            {["❚❚ pause", "+ inject event", "⑂ fork here", "export"].map(
              (b) => (
                <span key={b} className="border border-line px-3 py-2">
                  {b}
                </span>
              ),
            )}
          </span>
        </div>
        <div className="grid lg:grid-cols-[300px_1fr_300px]">
          <aside className="space-y-4 border-line p-5 lg:border-r">
            <p className="text-muted">CHARACTERS · MOOD</p>
            {CHARACTERS.map((c) => (
              <div key={c.name}>
                <p className="flex justify-between">
                  <span className="flex items-center gap-2">
                    <Avatar name={c.name} size={14} />@ {c.name}
                  </span>
                  <span className={c.mood < 0 ? "text-ember" : ""}>
                    {c.mood > 0 ? "+" : ""}
                    {c.mood.toFixed(1)}
                  </span>
                </p>
                <p className="text-muted">{c.role}</p>
                <MoodBar mood={c.mood} />
              </div>
            ))}
          </aside>
          <div className="space-y-3 p-5 font-display text-sm">
            {POSTS.map((p) => (
              <div
                key={p.who + p.meta}
                className="flex gap-3 border border-line bg-ink/60 px-4 py-3"
              >
                <Avatar name={p.who} size={28} />
                <div>
                  <p className="font-mono text-xs">
                    @{p.who} <span className="text-muted">{p.meta}</span>
                  </p>
                  <p className="mt-1">{p.text}</p>
                </div>
              </div>
            ))}
            <p className="border border-ember border-dashed px-4 py-3 font-mono text-ember text-xs">
              ⚡ round 4 · event injected by you — Lumen announces offline mode.
            </p>
            <div className="flex gap-3 border border-line bg-ink/60 px-4 py-3">
              <Avatar name="bruno" size={28} />
              <div>
                <p className="font-mono text-xs">
                  @bruno <span className="text-muted">posted r4</span>
                </p>
                <p className="mt-1">
                  Offline mode changes it. Upgrading today.
                </p>
              </div>
            </div>
            <div className="pt-3 font-mono text-xs leading-6">
              <p className="text-muted">private chat · you ↔ @eli</p>
              <p>
                <span className="text-ember">you ›</span> what would change your
                mind?
              </p>
              <p>
                <span className="text-muted">eli ›</span> A student tier, or a
                changelog that shows where the extra $5 goes.
              </p>
            </div>
          </div>
          <aside className="space-y-6 border-line p-5 lg:border-l">
            <div>
              <p className="text-muted">TIMELINE</p>
              <pre className="mt-3 leading-5">
                ●─●─●─● r3 saved{"\n"}
                {"      ├─● A · $9\n      └─"}
                <span className="text-ember">●─● B · $14</span>
              </pre>
              <p className="mt-2 text-ember">⚡ r4 offline mode</p>
            </div>
            <div>
              <p className="text-muted">USAGE · YOUR SUBSCRIPTION</p>
              <p className="mt-3">
                [{"█".repeat(11)}
                <span className="text-dim">{"░".repeat(4)}</span>] 73%
              </p>
              <p className="mt-2 text-muted">
                auto-pause at 90% of the window. resumes when your limit resets.
              </p>
            </div>
            <div>
              <p className="text-muted">REPORT · DRAFT</p>
              <p className="mt-3">
                Top objection: price without new value (4 of 6).
              </p>
              <p className="mt-2 text-muted">↳ linked to r2 · r3 posts</p>
            </div>
          </aside>
        </div>
      </Panel>
    </section>
  );
}

/* ---------- 03 branching ---------- */

function Branching() {
  return (
    <section className="grid items-center gap-12 py-24 lg:grid-cols-2">
      <div>
        <Eyebrow n="03">branching</Eyebrow>
        <h2 className="mt-4 font-medium text-5xl tracking-tight">
          Save a moment.
          <br />
          Fork the future.
        </h2>
        <p className="mt-4 max-w-[580px] text-lg text-paper/80 leading-relaxed">
          Freeze the community at any round and split it into alternate paths.
          Same people, same memories, one different decision — then compare how
          each world unfolds.
        </p>
      </div>
      <Panel className="p-6 font-mono text-muted text-xs">
        <svg
          viewBox="0 0 520 120"
          className="w-full"
          aria-label="Timeline forks at round 3 into A (keep $9) and B (move to $14)"
        >
          <line x1="20" y1="45" x2="200" y2="45" stroke="var(--color-ember)" />
          <path
            d="M200 45 V15 H320 M200 45 V95 H320"
            fill="none"
            stroke="var(--color-dim)"
          />
          {[20, 65, 110, 155].map((x) => (
            <circle key={x} cx={x} cy="45" r="4" fill="var(--color-ember)" />
          ))}
          {[230, 275, 320].flatMap((x) => [
            <circle
              key={`a${x}`}
              cx={x}
              cy="15"
              r="4"
              fill="var(--color-dim)"
            />,
            <circle
              key={`b${x}`}
              cx={x}
              cy="95"
              r="4"
              fill="var(--color-dim)"
            />,
          ])}
          <text x="350" y="19" fill="currentColor" fontSize="12">
            A · keep $9
          </text>
          <text x="350" y="99" fill="currentColor" fontSize="12">
            B · move to $14
          </text>
          <text x="70" y="80" fill="currentColor" fontSize="12">
            ↑ saved at round 3
          </text>
        </svg>
        <p className="mt-4">A sentiment … objections …</p>
        <p>B sentiment … objections …</p>
      </Panel>
    </section>
  );
}

/* ---------- 04 spellbook ---------- */

const FEATURES = [
  ["Communities", "Create and tune communities of agents around any question."],
  [
    "Characters with memory",
    "Profiles, relationships and memory that persists across rounds.",
  ],
  ["Grounded context", "Seed the world with your own texts and documents."],
  [
    "Round-based simulation",
    "Every post, reply and disagreement, visible as it happens.",
  ],
  ["Live interventions", "Inject events and change conditions mid-experiment."],
  ["One-on-one chats", "Pull any character aside and ask them why."],
  [
    "Branching scenarios",
    "Save a moment, fork it, and compare alternate futures.",
  ],
  [
    "Traceable reports",
    "Findings linked back to the moments that produced them.",
  ],
  ["Usage control", "Pause and resume around your providers' limits."],
  ["Export & share", "Package scenarios and experiments for others to run."],
];

const QUESTIONS = [
  ["our customers saw this product tomorrow?", "product reactions"],
  ["we charged $9 instead of $14?", "pricing · A/B branch"],
  ["this headline hit the group chat?", "how news spreads"],
  ["the forum banned anonymous posts?", "community rules"],
  ["a dragon moved into the village?", "fiction · social dynamics"],
];

function Spellbook() {
  return (
    <section id="features" className="scroll-mt-24 py-24">
      <Eyebrow n="04">the spellbook</Eyebrow>
      <h2 className="mt-4 max-w-[640px] font-medium text-5xl tracking-tight">
        Everything you need to run an experiment.
      </h2>
      <div className="mt-12 grid border-line border-t border-l sm:grid-cols-2 lg:grid-cols-4">
        {FEATURES.map(([title, body], i) => (
          <div
            key={title}
            className="min-h-[200px] border-line border-r border-b p-6"
          >
            <p className="font-mono text-muted text-xs">
              [{String(i + 1).padStart(2, "0")}]
            </p>
            <h3 className="mt-3 font-medium text-lg">{title}</h3>
            <p className="mt-2 text-paper/75 text-sm leading-relaxed">{body}</p>
          </div>
        ))}
      </div>

      <p className="mt-20 font-mono text-muted text-xs">
        things people ask it ↓
      </p>
      <ul className="mt-4 border-line border-t">
        {QUESTIONS.map(([q, tag]) => (
          <li
            key={q}
            className="flex flex-wrap items-baseline justify-between gap-2 border-line border-b py-6"
          >
            <span className="font-medium text-3xl tracking-tight">
              <span className="text-muted">What if</span> {q}
            </span>
            <span className="font-mono text-ember text-xs">{tag}</span>
          </li>
        ))}
      </ul>
      <p className="mt-6 font-mono text-muted text-xs">
        for the curious · researchers · creators · developers · product teams
      </p>
    </section>
  );
}

/* ---------- 05 local-first ---------- */

const PILLARS = [
  [
    "{ }",
    "Open source",
    `Read the code, fork it, extend it. Licensed under ${LICENSE}.`,
  ],
  [
    "[_]",
    "A native app",
    "A real Mac app: SwiftUI, a 4 MB download, Apple silicon and Intel. No account on our side.",
  ],
  [
    "~/",
    "Stored locally",
    "Communities, settings and history live on your disk. When you use an external provider, only the data a round needs is sent to it for processing.",
  ],
  [
    "<>",
    "Bring your own AI",
    "Use the subscriptions you already pay for through each provider's integrations — or API keys and local models. Sorcerer paces itself, pauses at your limits and picks up where it left off.",
  ],
];

const MACHINE = `┌─ your machine ───────────────┐
│                              │
│  sorcerer.app             ●  │
│   ├── communities/           │
│   ├── characters/            │
│   ├── history/               │
│   └── settings               │
│                              │
└──────────────┬───────────────┘
               │
               │  only what a round needs
               │
       ┌───────┼───────┐
       ▼       ▼       ▼
 subscription api key local model`;

function LocalFirst() {
  return (
    <section id="local" className="scroll-mt-24 py-24">
      <Eyebrow n="05">your machine, your models</Eyebrow>
      <h2 className="mt-4 max-w-[640px] font-medium text-5xl tracking-tight">
        Open source. Native. Local by default.
      </h2>
      <div className="mt-12 grid items-center gap-12 lg:grid-cols-2">
        <Panel className="overflow-x-auto p-6">
          <pre className="font-mono text-muted text-xs leading-5">
            {MACHINE}
          </pre>
        </Panel>
        <ul className="border-line border-t">
          {PILLARS.map(([icon, title, body]) => (
            <li key={title} className="flex gap-6 border-line border-b py-6">
              <span className="w-8 shrink-0 font-mono text-ember text-sm">
                {icon}
              </span>
              <div>
                <h3 className="font-medium text-lg">{title}</h3>
                <p className="mt-1 text-paper/75 text-sm leading-relaxed">
                  {body}
                </p>
              </div>
            </li>
          ))}
        </ul>
      </div>
      <p className="mt-12 flex flex-col gap-2 border border-line border-dashed p-6 text-paper/80 sm:flex-row sm:gap-6">
        <span className="shrink-0 font-mono text-ember text-xs">
          ! a note on results
        </span>
        Simulations surface possible reactions, objections and consequences.
        Treat them as hypotheses to investigate — they don't replace evidence
        from the real world.
      </p>
    </section>
  );
}

/* ---------- final CTA + footer ---------- */

function FinalCta() {
  return (
    <section
      id="download"
      className="flex scroll-mt-24 flex-col items-center py-28 text-center"
    >
      <Pixels rows={HAT} size={10} />
      <div className="mt-10">
        <Wordmark />
      </div>
      <h2 className="mt-8 font-medium text-4xl tracking-tight sm:text-5xl">
        Ask better questions before you act.
      </h2>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Btn href={DOWNLOAD_URL} primary>
          ↓ download for macOS
        </Btn>
        <Btn href={GITHUB_URL}>★ star on GitHub</Btn>
        <Btn href={INSTALL_URL}>how to install →</Btn>
      </div>
      <p className="mt-6 max-w-[520px] font-mono text-muted text-xs leading-5">
        Sorcerer isn't signed with a paid Apple developer account, so macOS asks
        once before the first launch. Open it, then System Settings › Privacy
        &amp; Security › Open Anyway.
      </p>
      <code className="mt-8 border border-line px-4 py-3 font-mono text-sm">
        <span className="text-ember">$</span> git clone {GITHUB_URL}
      </code>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-line border-t">
      <div className="mx-auto flex max-w-[1248px] flex-wrap items-center justify-between gap-4 px-6 py-8 font-mono text-muted text-xs">
        <span className="flex items-center gap-3">
          <Pixels rows={HAT} size={1.4} /> sorcerer · open source · inspired by
          MiroFish
        </span>
        <span className="flex gap-6">
          <a href={DOCS_URL} className="hover:text-paper">
            docs
          </a>
          <a href={GITHUB_URL} className="hover:text-paper">
            github
          </a>
          <a href={CHANGELOG_URL} className="hover:text-paper">
            changelog
          </a>
          <span>license · {LICENSE}</span>
        </span>
      </div>
    </footer>
  );
}
