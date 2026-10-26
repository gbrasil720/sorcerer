import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { Avatar, HAT, Meter, Pixels, signed } from "@/components/pixels";

export const Route = createFileRoute("/")({
  component: Landing,
});

const REPO = "gbrasil720/sorcerer";
const GITHUB_URL = `https://github.com/${REPO}`;
// Always the newest release: the release workflow uploads Sorcerer.dmg to each one.
const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Sorcerer.dmg`;
const DOCS_URL = `${GITHUB_URL}#readme`;
const INSTALL_URL = `${GITHUB_URL}#install`;
const CHANGELOG_URL = `${GITHUB_URL}/releases`;
const ISSUES_URL = `${GITHUB_URL}/issues/new/choose`;
// Downloading with curl skips the quarantine flag that makes macOS block unsigned apps.
const INSTALL_CMD = "curl -fsSL https://sorcererapp.dev/install.sh | sh";
const VERSION = "v0.8";
const LICENSE = "MIT";

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

const reducedMotion = () =>
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Advances 0, 1, 2… every `ms`, wrapping at `n`; stays at the last step with reduced motion. */
function useStep(n: number, ms: number) {
  const [step, setStep] = useState(0);
  useEffect(() => {
    if (reducedMotion()) {
      setStep(n - 1);
      return;
    }
    const t = setInterval(() => setStep((s) => (s + 1) % n), ms);
    return () => clearInterval(t);
  }, [n, ms]);
  return step;
}

export function Landing() {
  return (
    <div
      id="top"
      className="min-h-svh bg-ink font-display text-paper antialiased selection:bg-ember selection:text-ink"
    >
      <Announcement />
      <Nav />
      <main>
        <Hero />
        <Preview />
        <Wrap>
          <BuiltFor />
          <HowItWorks />
          <Inside />
        </Wrap>
        <UseCases />
        <Wrap>
          <YourAI />
          <OpenSource />
        </Wrap>
        <Band />
        <Wrap>
          <Faq />
        </Wrap>
        <FinalCta />
      </main>
      <Footer />
    </div>
  );
}

/* ---------- shared bits ---------- */

const Wrap = ({ children }: { children: React.ReactNode }) => (
  <div className="mx-auto max-w-[1288px] px-6">{children}</div>
);

function Eyebrow({ children }: { children: string }) {
  return <p className="font-mono text-ember text-sm">— {children}</p>;
}

function H2({
  children,
  small,
}: {
  children: React.ReactNode;
  small?: boolean;
}) {
  return (
    <h2
      className={`mt-5 max-w-[820px] font-medium leading-[1.02] tracking-[-0.035em] ${small ? "text-[clamp(36px,4.2vw,60px)]" : "text-[clamp(40px,5.4vw,76px)]"}`}
    >
      {children}
    </h2>
  );
}

const Card = ({
  className = "",
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) => (
  <div className={`rounded-xl border border-line bg-panel ${className}`}>
    {children}
  </div>
);

function Btn({
  href,
  primary,
  children,
  className = "",
}: {
  href: string;
  primary?: boolean;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={`inline-flex h-12 items-center justify-center rounded-md border px-5 font-mono text-[15px] transition-colors ${
        primary
          ? "border-ember bg-ember text-ink hover:bg-ember/90"
          : "border-line text-paper hover:border-paper/40"
      } ${className}`}
    >
      {children}
    </a>
  );
}

/** The one-line installer with a copy button. */
function InstallCommand({ className = "" }: { className?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div
      className={`flex items-center gap-3 rounded-md border border-line bg-panel py-2 pr-2 pl-4 font-mono text-[13px] ${className}`}
    >
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap">
        <span className="select-none text-ember">$ </span>
        {INSTALL_CMD}
      </code>
      <button
        type="button"
        onClick={() => {
          navigator.clipboard.writeText(INSTALL_CMD);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
        className="shrink-0 rounded border border-line px-2 py-1 text-muted text-xs transition-colors hover:text-paper"
      >
        {copied ? "copied" : "copy"}
      </button>
    </div>
  );
}

/* ---------- top ---------- */

function Announcement() {
  return (
    <a
      href={GITHUB_URL}
      className="flex items-center justify-center gap-3 border-line border-b bg-[#14110e] px-4 py-2.5 font-mono text-[13px] text-paper/90 transition-colors hover:text-paper"
    >
      <Pixels rows={HAT} size={1.2} />
      <span>Sorcerer {VERSION} is open source</span>
      <span className="text-muted">·</span>
      <span className="text-ember">star it on GitHub →</span>
    </a>
  );
}

function Nav() {
  const stars = useStars();
  const links = [
    ["How it works", "#how"],
    ["Features", "#features"],
    ["Your AI", "#ai"],
    ["Open source", "#open"],
    ["FAQ", "#faq"],
    ["Viewer", "/view"],
    ["Docs", DOCS_URL],
  ];
  return (
    <header className="sticky top-0 z-40 border-line border-b bg-ink/85 backdrop-blur">
      <nav
        aria-label="Main"
        className="mx-auto flex h-[66px] max-w-[1288px] items-center justify-between gap-6 px-6"
      >
        <div className="flex items-center gap-8">
          <a href="#top" className="flex items-center gap-3">
            <Pixels rows={HAT} size={2.2} />
            <span className="font-mono font-semibold text-lg">sorcerer</span>
          </a>
          <div className="hidden items-center gap-6 text-[15px] text-paper/75 lg:flex">
            {links.map(([label, href]) => (
              <a key={label} href={href} className="hover:text-paper">
                {label}
              </a>
            ))}
          </div>
        </div>
        <div className="flex items-center gap-2.5">
          <a
            href={GITHUB_URL}
            className="hidden h-10 items-center rounded-md border border-line px-4 font-mono text-sm hover:border-paper/40 sm:inline-flex"
          >
            ★ {stars ?? "star"}
          </a>
          <a
            href="#download"
            className="inline-flex h-10 items-center rounded-md bg-ember px-4 font-mono text-ink text-sm hover:bg-ember/90"
          >
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}

function Hero() {
  return (
    <section className="mx-auto max-w-[1288px] px-6 pt-24 pb-20 sm:pt-28">
      <p className="flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-muted text-sm">
        <span className="text-ember">●</span> the hypothesis engine
        <span>·</span> open source <span>·</span> runs on your machine
      </p>
      <h1 className="mt-10 font-medium text-[clamp(48px,8vw,118px)] leading-[0.92] tracking-[-0.045em]">
        Create a community.
        <br />
        Explore a hypothesis.
        <br />
        <span className="text-ember">Watch what happens.</span>
      </h1>
      <div className="mt-12 flex flex-col justify-between gap-10 lg:flex-row lg:items-end">
        <p className="max-w-[560px] text-[22px] text-paper/75 leading-snug">
          Sorcerer brings small worlds of AI characters to life on your
          computer, powered by the AI you already pay for. Ask “what if…?” and
          watch opinions form, collide and branch.
        </p>
        <div className="flex w-full max-w-[500px] flex-col gap-3">
          <div className="flex gap-3">
            <Btn href={DOWNLOAD_URL} primary className="flex-1">
              ↓ Download for macOS
            </Btn>
            <Btn href={GITHUB_URL}>★ Star on GitHub</Btn>
          </div>
          <InstallCommand className="w-full" />
          <p className="font-mono text-muted text-xs leading-5">
            free · macOS 15+ · Apple silicon &amp; Intel. The Terminal install
            opens right away; the .dmg asks once.{" "}
            <a href={INSTALL_URL} className="text-paper underline">
              why?
            </a>
          </p>
        </div>
      </div>
    </section>
  );
}

/* ---------- the live app preview ---------- */

type Item =
  | {
      kind: "post";
      round: number;
      who: string;
      to?: string;
      mood: number;
      text: string;
      r: [number, number, number];
    }
  | { kind: "event"; round: number; text: string };

const SCRIPT: Item[] = [
  {
    kind: "post",
    round: 1,
    who: "ada",
    mood: -0.2,
    text: "$14 a month for notes? I’ll wait and see what actually changes.",
    r: [2, 1, 3],
  },
  {
    kind: "post",
    round: 1,
    who: "bruno",
    mood: 0.4,
    text: "If sync gets faster, I’d pay it.",
    r: [1, 2, 1],
  },
  {
    kind: "post",
    round: 2,
    who: "chen",
    mood: -0.5,
    text: "Is there a student plan? That’s the real question.",
    r: [3, 3, 0],
  },
  {
    kind: "post",
    round: 2,
    who: "dara",
    to: "ada",
    mood: -0.3,
    text: "For a team of eight that’s $40 more a month. I need a reason to sign off.",
    r: [1, 2, 0],
  },
  {
    kind: "post",
    round: 3,
    who: "eli",
    mood: -0.7,
    text: "A price hike with no new features reads as a cash grab.",
    r: [4, 3, 2],
  },
  {
    kind: "post",
    round: 3,
    who: "fumi",
    to: "eli",
    mood: 0.4,
    text: "Annual at $120 would soften this a lot.",
    r: [1, 2, 1],
  },
  { kind: "event", round: 4, text: "Lumen announces offline mode." },
  {
    kind: "post",
    round: 4,
    who: "bruno",
    mood: 0.8,
    text: "Offline mode changes it. Upgrading today.",
    r: [2, 4, 0],
  },
  {
    kind: "post",
    round: 4,
    who: "ada",
    to: "bruno",
    mood: 0.3,
    text: "Fine — offline mode is the thing I wanted.",
    r: [0, 3, 0],
  },
  {
    kind: "post",
    round: 5,
    who: "eli",
    to: "fumi",
    mood: -0.1,
    text: "Better. Still want a student tier before I recommend it.",
    r: [1, 2, 1],
  },
  {
    kind: "post",
    round: 5,
    who: "chen",
    mood: -0.1,
    text: "Offline is nice but $14 is still a lot on a student budget.",
    r: [0, 2, 0],
  },
];
const CAST = ["ada", "bruno", "chen", "dara", "eli", "fumi"];
const START: Record<string, number> = {
  ada: 0,
  bruno: 0.2,
  chen: -0.2,
  dara: 0,
  eli: -0.3,
  fumi: 0.3,
};
const SPOTS: Record<string, [number, number]> = {
  ada: [14, 18],
  chen: [70, 30],
  dara: [20, 62],
  fumi: [74, 62],
  eli: [46, 86],
  bruno: [52, 8],
};
const TIES = [
  ["ada", "bruno"],
  ["ada", "dara"],
  ["eli", "fumi"],
  ["chen", "eli"],
  ["bruno", "fumi"],
];

function Stars({ count = 140 }: { count?: number }) {
  const stars = useMemo(
    () =>
      Array.from({ length: count }, (_, i) => ({
        x: (i * 73.13) % 100,
        y: (i * 41.7 + (i % 7) * 13) % 100,
        c: ["·", "+", "*", "·", "."][i % 5],
        ember: i % 23 === 0,
      })),
    [count],
  );
  return (
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0 overflow-hidden font-mono text-[11px]"
    >
      {stars.map((s, i) => (
        <span
          key={i}
          className={`absolute ${s.ember ? "text-ember/70" : "text-paper/20"}`}
          style={{ left: `${s.x}%`, top: `${s.y}%` }}
        >
          {s.c}
        </span>
      ))}
    </div>
  );
}

function Preview() {
  // One step per post or event, then a short hold before the round replays.
  const step = useStep(SCRIPT.length + 3, 1700);
  // Start with a few posts on screen so the feed never looks empty.
  const shown = SCRIPT.slice(0, Math.min(Math.max(step + 1, 4), SCRIPT.length));
  const round = shown.at(-1)?.round ?? 1;
  const moods = { ...START };
  for (const it of shown) if (it.kind === "post") moods[it.who] = it.mood;
  const talking = new Set(
    shown
      .filter((it) => it.kind === "post" && it.round === round)
      .map((it) => (it.kind === "post" ? it.who : "")),
  );
  const eliTurned = shown.length >= 10;
  const used = 52 + shown.length * 1;

  return (
    <section
      aria-label="Product preview"
      className="relative overflow-hidden border-line border-y py-16 sm:py-20"
    >
      <Stars />
      <div className="relative mx-auto max-w-[1288px] px-6">
        <div className="relative">
          <div className="overflow-hidden rounded-xl border border-line bg-ink shadow-[0_40px_120px_-40px_rgba(240,119,58,0.25)]">
            <div className="grid h-[620px] grid-cols-1 md:grid-cols-[230px_1fr] lg:grid-cols-[230px_1fr_330px]">
              <PreviewSidebar used={used} />
              <div className="flex min-w-0 flex-col border-line md:border-l">
                <div className="flex h-12 items-center justify-between gap-3 border-line border-b px-4 font-mono text-xs">
                  <div className="flex min-w-0 items-center gap-2 overflow-hidden whitespace-nowrap">
                    <span>lumen-pricing</span>
                    <span className="text-muted">/</span>
                    <span className="text-ember">branch B · $14</span>
                    <span className="rounded border border-line px-1.5 py-0.5 text-muted">
                      round {round}
                    </span>
                    <span className="hidden text-ember 2xl:inline">
                      <span className="motion-safe:animate-pulse">●</span>{" "}
                      running
                    </span>
                  </div>
                  <div className="hidden gap-1.5 whitespace-nowrap xl:flex">
                    <span className="rounded bg-ember px-2.5 py-1 text-ink">
                      ❚❚ pause
                    </span>
                    {["step ›", "⑂ fork", "report"].map((b) => (
                      <span
                        key={b}
                        className="rounded border border-line px-2.5 py-1"
                      >
                        {b}
                      </span>
                    ))}
                  </div>
                </div>
                <div className="flex items-center justify-between px-4 py-3 font-mono text-xs">
                  <div className="flex rounded-md border border-line p-0.5">
                    {["feed", "world", "graph"].map((t, i) => (
                      <span
                        key={t}
                        className={`rounded px-2.5 py-1 ${i === 0 ? "bg-line text-paper" : "text-muted"}`}
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                  <span className="hidden text-muted sm:inline">
                    filter: all characters · all rounds
                  </span>
                </div>
                <div className="flex min-h-0 flex-1 flex-col justify-end gap-2 overflow-hidden px-4">
                  {shown.map((it, i) =>
                    it.kind === "event" ? (
                      <div
                        key={i}
                        className="shrink-0 rounded-md border border-ember/70 border-dashed px-3 py-2.5 font-mono text-ember text-xs"
                      >
                        ⚡ event · injected by you — {it.text}
                      </div>
                    ) : (
                      <div
                        key={i}
                        className="flex shrink-0 gap-3 rounded-md border border-line bg-panel px-3 py-2.5 motion-safe:animate-[fadein_.5s_ease-out]"
                      >
                        <Avatar name={it.who} size={30} />
                        <div className="min-w-0">
                          <p className="font-mono text-[11px] text-muted">
                            <span className="font-semibold text-paper">
                              @{it.who}
                            </span>{" "}
                            {it.to ? `replied to @${it.to}` : "posted"}{" "}
                            <span className={it.mood < 0 ? "text-ember" : ""}>
                              mood {signed(it.mood)}
                            </span>
                          </p>
                          <p className="mt-0.5 text-[14px]">{it.text}</p>
                          <p className="mt-1 font-mono text-[10px] text-muted">
                            ↩ {it.r[0]} &nbsp;+ {it.r[1]} &nbsp;− {it.r[2]}{" "}
                            &nbsp;ask why ›
                          </p>
                        </div>
                      </div>
                    ),
                  )}
                </div>
                <div className="px-4 pt-3 pb-2">
                  <div className="flex items-center justify-between rounded-md border border-line px-3 py-2.5 font-mono text-muted text-xs">
                    <span>
                      <span className="text-ember">⚡</span> Inject an event or
                      change a condition…
                    </span>
                    <span>⌘E · ↵ at r{round + 1}</span>
                  </div>
                  <div className="mt-2 flex flex-wrap items-center gap-1.5 font-mono text-[11px] text-muted">
                    try:
                    {[
                      "competitor cuts price",
                      "press review",
                      "sync outage",
                      "student plan",
                    ].map((c) => (
                      <span
                        key={c}
                        className="rounded-full border border-line px-2 py-0.5 text-paper/80"
                      >
                        {c}
                      </span>
                    ))}
                  </div>
                </div>
                <div className="flex justify-between gap-4 border-line border-t px-4 py-2 font-mono text-[10px] text-muted">
                  <span>● saved locally · ~/Sorcerer/lumen-pricing</span>
                  <span className="hidden sm:inline">
                    {(32 + shown.length * 1.8).toFixed(1)}k tokens this run ·
                    Claude subscription
                  </span>
                </div>
              </div>
              <PreviewInspector moods={moods} talking={talking} round={round} />
            </div>
          </div>

          {/* Floating notes around the window */}
          <Callout className="top-24 -left-4 hidden md:flex" show={eliTurned}>
            <Avatar name="eli" size={28} />
            <span>
              <span className="text-paper">@eli</span> changed his mind
              <br />
              <span className="text-ember">−0.7 → −0.1 · r5</span>
            </span>
          </Callout>
          <Callout className="top-12 -right-4 hidden lg:flex" show>
            <span className="text-paper">
              ●─●─◆ fork saved
              <br />
              <span className="pl-7 text-ember">└─● branch B · $14</span>
            </span>
          </Callout>
          <Callout className="bottom-14 -left-4 hidden md:flex" show>
            <span>
              your subscription
              <br />
              <Meter value={used / 100} cells={10} />{" "}
              <span className="text-paper">{used}%</span>
              <br />
              auto-pause at 90%
            </span>
          </Callout>
          <Callout className="right-0 bottom-4 hidden lg:flex" show>
            <span>
              <span className="text-ember">●</span> ~/Sorcerer · stored locally
            </span>
          </Callout>
        </div>
      </div>
    </section>
  );
}

function Callout({
  className,
  show,
  children,
}: {
  className: string;
  show: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      aria-hidden
      className={`absolute z-10 items-center gap-3 rounded-lg border border-line bg-panel/95 px-4 py-3 font-mono text-muted text-xs leading-5 shadow-2xl backdrop-blur motion-safe:transition-all motion-safe:duration-500 ${
        show ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"
      } ${className}`}
    >
      {children}
    </div>
  );
}

function PreviewSidebar({ used }: { used: number }) {
  const row = "flex items-center justify-between rounded px-2 py-1.5";
  return (
    <aside className="hidden flex-col bg-[#0e0e0d] p-3 font-mono text-[12px] md:flex">
      <div className="flex gap-1.5 px-1 pt-1 pb-4">
        {["#ff5f57", "#febc2e", "#28c840"].map((c) => (
          <span
            key={c}
            className="size-2.5 rounded-full"
            style={{ background: c }}
          />
        ))}
      </div>
      <div className="flex items-center justify-between px-1">
        <span className="flex items-center gap-2 font-semibold text-sm">
          <Pixels rows={HAT} size={1.5} /> sorcerer
        </span>
        <span className="grid size-6 place-items-center rounded border border-line">
          +
        </span>
      </div>
      <div className="mt-3 flex justify-between rounded border border-line px-2 py-1.5 text-muted">
        <span>/ Search</span>
        <span>⌘K</span>
      </div>
      <p className="mt-5 px-2 text-[10px] text-muted tracking-widest">
        EXPERIMENTS
      </p>
      <div className="mt-1.5 flex flex-col">
        <span className={row}>
          <span>
            <span className="text-ember">●</span> lumen-pricing
          </span>
          <span className="text-muted">r5</span>
        </span>
        <span className={`${row} pl-6 text-muted`}>
          <span>⑂ A · $9</span>
          <span>r5</span>
        </span>
        <span className={`${row} bg-line/60 pl-6`}>
          <span>⑂ B · $14</span>
          <span className="text-ember">live</span>
        </span>
        {[
          ["village-dragon", "r22"],
          ["rumor-spread", "❚❚"],
          ["forum-rules", "r8"],
        ].map(([n, r]) => (
          <span key={n} className={row}>
            <span>{n}</span>
            <span className="text-muted">{r}</span>
          </span>
        ))}
      </div>
      <p className="mt-5 px-2 text-[10px] text-muted tracking-widest">
        COMMUNITIES
      </p>
      {[
        ["Lumen customers", 6],
        ["Riverside village", 24],
        ["Forum regulars", 40],
      ].map(([n, c]) => (
        <span key={n} className={`${row} font-display text-[13px]`}>
          <span>{n}</span>
          <span className="font-mono text-muted text-xs">{c}</span>
        </span>
      ))}
      <div className="mt-auto rounded border border-line p-2.5 text-[11px] text-muted">
        <p className="text-[10px] tracking-widest">YOUR SUBSCRIPTION</p>
        <p className="mt-1.5 flex items-center gap-2 text-paper">
          <Meter value={used / 100} cells={12} /> {used}%
        </p>
        <p className="mt-1">resets in 2h 14m · auto-pause 90%</p>
      </div>
      <div className="flex justify-between px-1 pt-3 text-[11px] text-muted">
        <span>~/Sorcerer · local</span>
        <span>⚙</span>
      </div>
    </aside>
  );
}

function PreviewInspector({
  moods,
  talking,
  round,
}: {
  moods: Record<string, number>;
  talking: Set<string>;
  round: number;
}) {
  return (
    <aside className="hidden flex-col border-line border-l bg-[#0e0e0d] font-mono text-xs lg:flex">
      <div className="border-line border-b p-4">
        <div className="flex justify-between text-[10px] text-muted tracking-widest">
          <span>WORLD</span>
          <span className="tracking-normal">
            6 agents · {talking.size} talking
          </span>
        </div>
        <div className="relative mt-3 h-[150px]">
          <svg className="absolute inset-0 size-full" aria-hidden>
            {TIES.map(([a, b]) => (
              <line
                key={a + b}
                x1={`${SPOTS[a][0] + 4}%`}
                y1={`${SPOTS[a][1] + 6}%`}
                x2={`${SPOTS[b][0] + 4}%`}
                y2={`${SPOTS[b][1] + 6}%`}
                stroke={
                  talking.has(a) && talking.has(b)
                    ? "var(--color-ember)"
                    : "var(--color-dim)"
                }
                strokeDasharray="2 4"
              />
            ))}
          </svg>
          {CAST.map((h) => (
            <span
              key={h}
              className={`absolute flex items-center gap-1.5 transition-colors ${talking.has(h) ? "text-paper" : "text-muted"}`}
              style={{ left: `${SPOTS[h][0]}%`, top: `${SPOTS[h][1]}%` }}
            >
              <Avatar
                name={h}
                size={16}
                className={talking.has(h) ? "ring-1 ring-ember" : "opacity-70"}
              />
              {h}
            </span>
          ))}
        </div>
      </div>
      <div className="border-line border-b p-4">
        <p className="text-[10px] text-muted tracking-widest">
          CHARACTERS · MOOD
        </p>
        <div className="mt-3 flex flex-col gap-2.5">
          {CAST.map((h) => (
            <div key={h} className="flex items-center gap-2.5">
              <Avatar name={h} size={16} />
              <span className="w-12">{h}</span>
              <Meter value={(moods[h] + 1) / 2} warn={moods[h] < -0.25} />
              <span className={`ml-auto ${moods[h] < 0 ? "text-muted" : ""}`}>
                {signed(moods[h])}
              </span>
            </div>
          ))}
        </div>
      </div>
      <div className="p-4">
        <p className="text-[10px] text-muted tracking-widest">TIMELINE</p>
        <pre className="mt-3 text-[11px] leading-5">
          <span className="text-muted">●─●─●─</span>
          <span className="text-ember">◆</span> r3{"\n"}
          {"      "}├─●{round > 3 ? "─●" : ""}{" "}
          <span className="text-muted">A · $9</span>
          {"\n"}
          {"      "}
          <span className="text-ember">
            └─●{"─●".repeat(Math.max(0, round - 3))}
          </span>{" "}
          B
        </pre>
        <p className="mt-3 text-[11px] text-ember">
          {round >= 4 ? "⚡ r4 offline mode" : "· no events"}
        </p>
      </div>
    </aside>
  );
}

/* ---------- built for ---------- */

function BuiltFor() {
  const stats: [React.ReactNode, string][] = [
    ["0", "accounts on our side"],
    [
      <>
        100<span className="text-ember">%</span>
      </>,
      "of your worlds stored locally",
    ],
    ["∞", "branches per world"],
    [
      <>
        BYO<span className="text-ember">·</span>AI
      </>,
      "subscriptions or local models",
    ],
  ];
  return (
    <section className="py-20">
      <div className="flex flex-col justify-between gap-5 lg:flex-row lg:items-center">
        <p className="font-mono text-muted text-sm">
          built for people who want better questions before they act
        </p>
        <div className="flex flex-wrap gap-2">
          {[
            "product teams",
            "researchers",
            "creators",
            "developers",
            "the curious",
          ].map((c) => (
            <span
              key={c}
              className="rounded-full border border-line px-4 py-2 font-mono text-sm"
            >
              {c}
            </span>
          ))}
        </div>
      </div>
      <div className="mt-8 grid grid-cols-2 overflow-hidden rounded-xl border border-line lg:grid-cols-4">
        {stats.map(([n, label], i) => (
          <div
            key={label}
            className={`border-line p-6 sm:p-8 ${i % 2 ? "border-l" : ""} ${i > 1 ? "max-lg:border-t" : ""} lg:[&:not(:first-child)]:border-l`}
          >
            <p className="font-medium text-[clamp(44px,5vw,64px)] leading-none tracking-tight">
              {n}
            </p>
            <p className="mt-4 font-mono text-muted text-sm">{label}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ---------- how it works ---------- */

const PIPE = [
  "question",
  "community",
  "context",
  "rounds",
  "branches",
  "report",
];
const STEPS = [
  {
    n: "01",
    tag: "summon",
    icon: "@",
    title: "Create a community",
    code: "community.summon(6)",
    rows: [
      ["personalities", "yes"],
      ["goals + ties", "yes"],
      ["memory", "persistent"],
    ],
  },
  {
    n: "02",
    tag: "ground",
    icon: "⎇",
    title: "Teach it your world",
    code: "context.add(repo, site, docs)",
    rows: [
      ["public", "everyone"],
      ["insider", "the team"],
      ["hidden", "nobody"],
    ],
  },
  {
    n: "03",
    tag: "cast",
    icon: "*",
    title: "Introduce a hypothesis",
    code: 'world.cast("what if…")',
    rows: [
      ["rounds", "visible"],
      ["events", "any time"],
      ["chats", "1:1"],
    ],
  },
  {
    n: "04",
    tag: "fork",
    icon: "⑂",
    title: "Compare futures",
    code: "moment.fork()",
    rows: [
      ["branches", "unlimited"],
      ["reports", "cited"],
      ["export", "share"],
    ],
  },
];

function HowItWorks() {
  const active = useStep(PIPE.length, 1400);
  return (
    <section id="how" className="scroll-mt-24 py-20">
      <Eyebrow>how it works</Eyebrow>
      <H2>From a question to a living world.</H2>
      <div className="mt-14 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-line px-6 py-5 font-mono text-[15px]">
        {PIPE.map((p, i) => (
          <span key={p} className="flex items-center gap-4">
            <span
              className={`transition-colors ${i === active ? "text-ember" : i === 0 ? "text-paper" : "text-muted"}`}
            >
              {p}
            </span>
            {i < PIPE.length - 1 && (
              <span className="hidden items-center text-dim sm:flex">
                <span className="h-px w-16 bg-dim" />
                <span className={i === active ? "text-ember" : ""}>
                  {i === active ? "◆" : "▸"}
                </span>
              </span>
            )}
          </span>
        ))}
      </div>
      <div className="mt-6 grid overflow-hidden rounded-xl border border-line sm:grid-cols-2 lg:grid-cols-4">
        {STEPS.map((s, i) => (
          <div
            key={s.n}
            className={`border-line p-6 ${i ? "max-sm:border-t sm:border-l" : ""} ${i === 2 ? "sm:max-lg:border-t sm:max-lg:border-l-0" : ""} ${i === 3 ? "sm:max-lg:border-t" : ""}`}
          >
            <div className="flex justify-between font-mono text-muted text-sm">
              <span>
                {s.n} · {s.tag}
              </span>
              <span className="text-ember">{s.icon}</span>
            </div>
            <h3 className="mt-5 font-medium text-2xl tracking-tight">
              {s.title}
            </h3>
            <code className="mt-5 block overflow-hidden whitespace-nowrap rounded-md border border-ember/25 bg-ember/[0.06] px-3 py-2.5 font-mono text-[13px] text-ember">
              {s.code}
            </code>
            <dl className="mt-5 font-mono text-sm">
              {s.rows.map(([k, v]) => (
                <div
                  key={k}
                  className="flex justify-between border-line border-b border-dashed py-2"
                >
                  <dt className="text-muted">{k}</dt>
                  <dd>{v}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ---------- inside a simulation ---------- */

function Feature({
  n,
  tag,
  title,
  body,
  flip,
  children,
}: {
  n: string;
  tag: string;
  title: string;
  body: string;
  flip?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="grid items-center gap-10 border-line border-t py-16 lg:grid-cols-2 lg:gap-16">
      <div className={flip ? "lg:order-2" : ""}>
        <p className="font-mono text-muted text-sm">
          {n} · {tag}
        </p>
        <h3 className="mt-4 font-medium text-[clamp(30px,3.4vw,44px)] leading-[1.05] tracking-[-0.03em]">
          {title}
        </h3>
        <p className="mt-5 max-w-[520px] text-lg text-paper/75 leading-relaxed">
          {body}
        </p>
      </div>
      <div className={flip ? "lg:order-1" : ""}>{children}</div>
    </div>
  );
}

const Trait = ({
  label,
  value,
  warn,
}: {
  label: string;
  value: number;
  warn?: boolean;
}) => (
  <span className="flex items-center gap-2">
    <span className="w-20 text-muted">{label}</span>
    <Meter value={value} cells={12} warn={warn} />
  </span>
);

function Inside() {
  return (
    <section id="features" className="scroll-mt-24 pt-20">
      <Eyebrow>inside a simulation</Eyebrow>
      <H2>Every character is someone.</H2>
      <div className="mt-14">
        <Feature
          n="01"
          tag="characters"
          title="They have a face, a past and an opinion."
          body="Personality, interests, goals, relationships and a memory that persists across rounds. Summon a cast or import 2–16 characters from a CSV, review them, and give each one a pixel portrait."
        >
          <Card className="p-6">
            <div className="flex items-center gap-4">
              <Avatar name="eli" size={72} />
              <div>
                <p className="font-medium text-2xl">@eli</p>
                <p className="text-paper/80">
                  Tech writer · skeptical by default
                </p>
                <p className="mt-1 font-mono text-muted text-xs">
                  23 memories · 4 ties
                </p>
              </div>
            </div>
            <div className="mt-5 grid gap-2 font-mono text-xs sm:grid-cols-2">
              <Trait label="skepticism" value={0.8} warn />
              <Trait label="curiosity" value={0.7} />
              <Trait label="frugality" value={0.6} />
              <Trait label="warmth" value={0.4} />
            </div>
            <ul className="mt-5 font-mono text-sm">
              {[
                "Saw the $14 announcement on the blog.",
                "Read @chen asking about a student plan.",
                "Argued with @fumi about annual pricing.",
                "Learned offline mode is coming.",
                "Softened — still wants a student tier.",
              ].map((m, i) => (
                <li key={m} className="flex gap-5 border-line border-t py-2.5">
                  <span className={i === 4 ? "text-ember" : "text-muted"}>
                    r{i + 1}
                  </span>
                  {m}
                </li>
              ))}
            </ul>
          </Card>
        </Feature>

        <Feature
          n="02"
          tag="conversations"
          title="Pull anyone aside and ask why."
          body="Chat one-on-one with any character mid-simulation. Conversations stay saved on your Mac, per branch. No chat transcripts are included in share exports. Off-the-record chats leave memories unchanged; in-world memories stay in the simulation."
          flip
        >
          <Card className="p-6">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-3 font-medium text-lg">
                <Avatar name="chen" size={28} /> Talk to @chen
              </span>
              <span className="rounded-full border border-line px-3 py-1 font-mono text-muted text-xs">
                off the record
              </span>
            </div>
            <p className="mt-6 ml-auto w-fit rounded-lg border border-line bg-line/50 px-4 py-2.5">
              Would a student plan change your mind?
            </p>
            <div className="mt-4 flex items-end gap-3">
              <Avatar name="chen" size={28} />
              <p className="rounded-lg border border-line px-4 py-2.5">
                Yes. At $14 I'd move to a free app — at half that I'd stay and
                tell my classmates.
              </p>
            </div>
            <p className="mt-5 font-mono text-muted text-xs">
              ↳ from memory · r2 student plan question · goal: save money
            </p>
          </Card>
        </Feature>

        <Feature
          n="03"
          tag="context"
          title="Teach the world what it's about."
          body="Point Sorcerer at a repository, a folder, a website or your notes. It writes a brief, and you decide which facts are public, which only insiders know, and which stay hidden."
        >
          <Card className="p-6">
            <div className="flex justify-between font-mono text-muted text-xs">
              <span>THE BRIEF · lumen-app/lumen</span>
              <span className="text-paper">✓ 214 files</span>
            </div>
            <ul className="mt-3">
              {[
                [
                  "public",
                  "Lumen is a note-taking app that syncs across devices.",
                ],
                ["public", "Pro costs $9 a month today."],
                ["insider", "Offline mode is in development."],
                ["hidden", "The $14 price is being considered."],
              ].map(([a, f]) => (
                <li
                  key={f}
                  className="flex items-center gap-4 border-line border-b py-3.5 last:border-0"
                >
                  <span
                    className={`w-20 shrink-0 rounded-full border px-2 py-1 text-center font-mono text-xs ${
                      a === "insider"
                        ? "border-ember text-ember"
                        : a === "hidden"
                          ? "border-line border-dashed text-muted"
                          : "border-line"
                    }`}
                  >
                    {a}
                  </span>
                  <span className={a === "hidden" ? "text-muted" : ""}>
                    {f}
                  </span>
                </li>
              ))}
            </ul>
          </Card>
        </Feature>

        <Feature
          n="04"
          tag="branches"
          title="Save a moment. Fork the future."
          body="Freeze the community at any round, replay how it got there, and split it. Same people, same memories, one different decision. Reports link every finding to the posts that caused it."
          flip
        >
          <Card className="p-6 font-mono text-sm">
            <svg viewBox="0 0 420 120" className="w-full" aria-hidden>
              <line
                x1="8"
                y1="50"
                x2="140"
                y2="50"
                stroke="var(--color-ember)"
                strokeWidth="1.5"
              />
              {[8, 40, 72, 104].map((x) => (
                <circle
                  key={x}
                  cx={x}
                  cy={50}
                  r={4}
                  fill="var(--color-ember)"
                />
              ))}
              <path
                d="M140 50 V14 H240 M140 50 V90 H240"
                fill="none"
                stroke="var(--color-dim)"
                strokeWidth="1.5"
              />
              <path
                d="M140 50 V90 H240"
                fill="none"
                stroke="var(--color-ember)"
                strokeWidth="1.5"
                strokeDasharray="3 3"
              />
              {[170, 205, 240].map((x) => (
                <g key={x}>
                  <circle cx={x} cy={14} r={3.5} fill="var(--color-muted)" />
                  <circle cx={x} cy={90} r={3.5} fill="var(--color-ember)" />
                </g>
              ))}
              <text
                x="256"
                y="18"
                fill="var(--color-muted)"
                fontSize="12"
                fontFamily="var(--font-mono)"
              >
                A · keep $9
              </text>
              <text
                x="256"
                y="94"
                fill="var(--color-paper)"
                fontSize="12"
                fontFamily="var(--font-mono)"
              >
                B · move to $14
              </text>
              <text
                x="60"
                y="80"
                fill="var(--color-muted)"
                fontSize="11"
                fontFamily="var(--font-mono)"
              >
                ↑ saved at round 3
              </text>
            </svg>
            <div className="mt-4 grid grid-cols-[auto_1fr_1fr] gap-x-6 gap-y-1.5 text-muted">
              <span>A</span>
              <span>
                sentiment <span className="text-paper">+0.3</span>
              </span>
              <span>
                upgraded <span className="text-paper">5 / 8</span>
              </span>
              <span className="text-ember">B</span>
              <span>
                sentiment <span className="text-paper">+0.2</span>
              </span>
              <span>
                upgraded <span className="text-paper">3 / 8</span>
              </span>
            </div>
          </Card>
        </Feature>

        <Feature
          n="05"
          tag="limits"
          title="Runs inside your limits."
          body="Sorcerer watches your Claude usage windows, pauses before you run out and picks up where it left off when your limit resets."
        >
          <Card className="p-6 font-mono text-sm">
            {[
              [
                "Claude · subscription",
                "5h window · pause at 90%",
                0.62,
                "62%",
              ],
              ["ChatGPT · subscription", "pauses if you're out", 0.21, "21%"],
              ["Ollama · local", "no limit", 0, "local"],
            ].map(([name, note, v, label]) => (
              <div key={name as string} className="mb-5">
                <div className="flex justify-between">
                  <span>{name}</span>
                  <span className="text-muted text-xs">{note}</span>
                </div>
                <div className="mt-2 flex items-center gap-3">
                  <Meter value={v as number} cells={38} />
                  <span className="text-xs">{label}</span>
                </div>
              </div>
            ))}
            <p className="rounded-md border border-line border-dashed px-3 py-2.5 text-xs">
              <span className="text-ember">❚❚</span> village-dragon paused at
              r22 <span className="text-muted">· resumes in 2h 14m</span>
            </p>
          </Card>
        </Feature>

        <Feature
          n="06"
          tag="actions & polls"
          title="Count what they do, ask what they think."
          body="Characters act as well as talk: upgrade, cancel, leave, invite a friend. Ask everyone a question at any round, off the record or in public, and every answer comes with a reason. Reports count all of it instead of guessing."
          flip
        >
          <Card className="p-6">
            <div className="flex items-center justify-between gap-3">
              <p className="font-medium text-lg">
                <span className="text-ember">? </span>Would you pay $14 a month?
              </p>
              <span className="shrink-0 font-mono text-muted text-xs">
                off the record · 6 answered
              </span>
            </div>
            <div className="mt-4 flex flex-col gap-2.5 font-mono text-sm">
              {(
                [
                  ["yes", 1, ["dana"]],
                  ["no", 3, ["kenji", "marisol", "rex"]],
                  ["not sure", 2, ["priya", "theo"]],
                ] as [string, number, string[]][]
              ).map(([o, n, who]) => (
                <div key={o} className="flex items-center gap-3">
                  <span className="w-20">{o}</span>
                  <span className="h-2 flex-1 bg-line">
                    <span
                      className="block h-full bg-ember/80"
                      style={{ width: `${(n / 6) * 100}%` }}
                    />
                  </span>
                  <span className="flex w-16 gap-0.5">
                    {who.map((w) => (
                      <Avatar key={w} name={w} size={16} />
                    ))}
                  </span>
                  <span className="w-4 text-right">{n}</span>
                </div>
              ))}
            </div>
            <ul className="mt-5 border-line border-t pt-3 text-sm">
              <li className="flex gap-3 py-1.5">
                <Avatar name="priya" size={18} />
                <span className="w-20 font-mono text-ember text-xs leading-5">
                  not sure
                </span>
                <span className="text-paper/80">
                  My trial elsewhere is holding up; show me what the extra $5
                  buys.
                </span>
              </li>
              <li className="flex items-center gap-3 rounded-md border border-ember/40 border-dashed px-3 py-2 font-mono text-xs">
                <span className="text-ember">◆</span>
                <Avatar name="kenji" size={16} /> @kenji{" "}
                <span className="text-ember">switch to a free app</span>
              </li>
            </ul>
          </Card>
        </Feature>
      </div>
    </section>
  );
}

/* ---------- use cases ---------- */

const ASKS: [string, string, string[]][] = [
  ["product", "our customers saw this tomorrow?", ["ada", "gus", "iris"]],
  ["news", "this headline hit the group chat?", ["chen", "dara", "eli"]],
  ["fiction", "a dragon moved into the village?", ["wren", "pip", "edda"]],
  ["policy", "the office went four days a week?", ["fumi", "osric", "lyra"]],
  ["story", "the king vanished overnight?", ["tobias", "hannah", "bruno"]],
];
const ASKS2: [string, string, string[]][] = [
  ["pricing", "we charged $9 instead of $14?", ["ada", "bruno", "chen"]],
  ["rules", "the forum banned anonymous posts?", ["dara", "eli", "fumi"]],
  ["launch", "we launched a week before our rival?", ["gus", "iris", "wren"]],
  ["community", "moderators had to be elected?", ["pip", "edda", "osric"]],
  [
    "onboarding",
    "signup asked for a credit card?",
    ["lyra", "tobias", "hannah"],
  ],
];

function AskRow({ items, reverse }: { items: typeof ASKS; reverse?: boolean }) {
  return (
    <div className="flex overflow-hidden">
      <div
        className={`flex shrink-0 gap-4 pr-4 ${reverse ? "marquee-rev" : "marquee"}`}
      >
        {[...items, ...items, ...items, ...items].map(([tag, q, who], i) => (
          <div
            key={i}
            className="w-[420px] shrink-0 rounded-xl border border-line bg-panel p-6"
          >
            <div className="flex justify-between">
              <span className="font-mono text-ember text-sm">{tag}</span>
              <span className="flex gap-1">
                {who.map((w) => (
                  <Avatar key={w} name={w} size={18} />
                ))}
              </span>
            </div>
            <p className="mt-4 text-xl leading-snug">
              <span className="text-muted">What if </span>
              {q}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

function UseCases() {
  return (
    <section aria-label="Use cases" className="border-line border-t py-24">
      <Wrap>
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <h2 className="font-medium text-[clamp(40px,5vw,64px)] tracking-[-0.035em]">
            What will you ask?
          </h2>
          <p className="font-mono text-muted text-sm">
            start from a template or ask your own
          </p>
        </div>
      </Wrap>
      <div className="mt-12 flex flex-col gap-4">
        <AskRow items={ASKS} />
        <AskRow items={ASKS2} reverse />
      </div>
    </section>
  );
}

/* ---------- your AI ---------- */

const PROVIDERS = [
  ["OL", "Ollama · qwen2.5:14b", "local · this Mac", "ready"],
  ["CL", "Claude", "via Claude Code · your subscription", "signed in"],
  ["GP", "ChatGPT", "via Codex CLI · your subscription", "signed in"],
  ["Ge", "Gemini", "via Gemini CLI", "ready"],
  ["LM", "LM Studio", "OpenAI-compatible · localhost:1234/v1", "ready"],
  ["{}", "Your API endpoint", "OpenAI-compatible · key in Keychain", "ready"],
];

function YourAI() {
  const [picked, setPicked] = useState(0);
  return (
    <section
      id="ai"
      className="grid scroll-mt-24 items-center gap-12 border-line border-t py-24 lg:grid-cols-2"
    >
      <div>
        <Eyebrow>bring your own AI</Eyebrow>
        <H2 small>The AI you already use. Your choice.</H2>
        <p className="mt-6 max-w-[520px] text-lg text-paper/75 leading-relaxed">
          Sorcerer finds the AI tools you're signed in to and uses each
          provider's own integration. Prefer local models? Use Ollama or LM
          Studio. You can also connect an OpenAI-compatible endpoint with your
          own key; API usage may be billed by that provider. Mix them per role:
          characters, reports and chats can each run on a different one.
        </p>
      </div>
      <Card className="p-2">
        <div className="flex justify-between px-3 py-3 font-mono text-muted text-xs tracking-widest">
          <span>CHARACTERS RUN ON</span>
        </div>
        <ul aria-label="Models">
          {PROVIDERS.map(([badge, name, sub, status], i) => {
            const soon = status === "soon";
            return (
              <li key={name}>
                <button
                  type="button"
                  disabled={soon}
                  aria-pressed={picked === i}
                  onClick={() => setPicked(i)}
                  className={`flex w-full items-center gap-4 rounded-lg px-3 py-3 text-left transition-colors ${
                    picked === i
                      ? "bg-line/70"
                      : soon
                        ? "opacity-55"
                        : "hover:bg-line/40"
                  }`}
                >
                  <span className="grid size-10 shrink-0 place-items-center rounded-md border border-line font-mono text-ember text-sm">
                    {badge}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block">{name}</span>
                    <span className="block font-mono text-muted text-xs">
                      {sub}
                    </span>
                  </span>
                  <span
                    className={`font-mono text-xs ${picked === i ? "text-ember" : "text-muted"}`}
                  >
                    {picked === i ? "● selected" : status}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      </Card>
    </section>
  );
}

/* ---------- open source ---------- */

const MACHINE = `┌─ your machine ─────────────────┐
│                                │
│  Sorcerer.app                  │
│  ~/Sorcerer                    │
│   ├── experiments/             │
│   ├── contexts/                │
│   └── settings.json            │
│                                │
└───────────────┬────────────────┘
                │  only what a round needs
       ┌────────┼────────┐
       ▼        ▼        ▼
  subscription  CLI   local model`;

function OpenSource() {
  const stars = useStars();
  const links = [
    [
      REPO,
      "The native app and this site",
      stars === null ? "★" : `★ ${stars}`,
      GITHUB_URL,
    ],
    [
      "releases",
      "Downloads and what changed in each version",
      "→",
      CHANGELOG_URL,
    ],
    ["docs", "Install, build, shortcuts and the export format", "→", DOCS_URL],
  ];
  return (
    <section id="open" className="scroll-mt-24 border-line border-t py-24">
      <Eyebrow>open source · local-first</Eyebrow>
      <H2>Your worlds live on your machine.</H2>
      <div className="mt-14 grid gap-5 lg:grid-cols-2">
        <Card className="overflow-x-auto p-8">
          <pre className="font-mono text-[13px] text-paper/85 leading-6">
            {MACHINE}
          </pre>
        </Card>
        <Card className="flex flex-col p-6">
          <p className="font-mono text-muted text-xs tracking-widest">
            REPOSITORY · {LICENSE}
          </p>
          <ul className="mt-2">
            {links.map(([title, sub, right, href]) => (
              <li key={title}>
                <a
                  href={href}
                  className="flex items-start justify-between gap-4 border-line border-b py-4 hover:text-ember"
                >
                  <span>
                    <span className="block font-mono">{title}</span>
                    <span className="mt-1 block text-muted text-sm">{sub}</span>
                  </span>
                  <span className="font-mono text-muted text-sm">{right}</span>
                </a>
              </li>
            ))}
          </ul>
          <p className="mt-auto rounded-md border border-line border-dashed px-4 py-3 text-paper/85 text-sm">
            <span className="text-ember">! </span>Simulated results are
            hypotheses to investigate, not evidence from the real world.
          </p>
        </Card>
      </div>
    </section>
  );
}

function Band() {
  const words = [
    "your AI",
    "your limits",
    "your worlds",
    "hypotheses, not evidence",
    "local-first",
    "open source",
  ];
  return (
    <div aria-hidden className="flex overflow-hidden border-line border-y py-7">
      <div className="marquee flex shrink-0 items-center gap-10 pr-10 font-mono text-[clamp(28px,3.4vw,44px)]">
        {[...words, ...words, ...words, ...words].map((w, i) => (
          <span
            key={i}
            className="flex shrink-0 items-center gap-10 whitespace-nowrap"
          >
            {w} <span className="text-[0.7em] text-ember">✦</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/* ---------- FAQ ---------- */

const FAQ = [
  [
    "Is Sorcerer free?",
    "Yes. It's free and open source (MIT), with no account and no server. It runs on the AI tools you're already signed in to, local models or your own endpoint. Remote API providers may charge for usage.",
  ],
  [
    "Where does my data live?",
    "In ~/Sorcerer on your Mac, as plain JSON you can read, back up or delete. When a round runs on Claude or ChatGPT, only what that round needs is sent to that provider; local Ollama and LM Studio servers keep inference on your Mac. Remote servers receive that context. OpenAI-compatible endpoint keys stay in Keychain; each CLI manages its own authentication.",
  ],
  [
    "Which AI can I use?",
    "Claude through Claude Code, ChatGPT through Codex CLI, Gemini CLI, Ollama, LM Studio or an OpenAI-compatible API endpoint. Pick a model per provider and a different one for characters, reports and chats.",
  ],
  [
    "What happens when I hit my limits?",
    "Sorcerer reads your Claude usage windows, pauses before you run out (at 90% by default) and resumes when the window resets. It can also spread rounds out so a long run fits in one window.",
  ],
  [
    "Can it tell me how many people would buy?",
    "It counts what characters do (upgrade, cancel, leave, invite) and what they answer in polls, so you get numbers like “3 of 8 upgraded”. They're counts from a small simulated community, useful to compare branches and spot objections, not a market forecast.",
  ],
  [
    "Are the results real research?",
    "No. Simulations surface possible reactions, objections and consequences. Treat them as hypotheses to investigate; they don't replace evidence from the real world.",
  ],
  [
    "How does it relate to MiroFish?",
    "Sorcerer is inspired by MiroFish but is a separate implementation: a native Mac app instead of a web service, running on the subscriptions you already have, made for curiosity and fun rather than forecasting.",
  ],
];

function Faq() {
  return (
    <section id="faq" className="scroll-mt-24 py-24">
      <Eyebrow>questions</Eyebrow>
      <H2>
        Before you
        <br />
        summon.
      </H2>
      <div className="mt-12 border-line border-t">
        {FAQ.map(([q, a]) => (
          <details key={q} className="group border-line border-b">
            <summary className="flex cursor-pointer list-none items-center justify-between py-6 font-medium text-xl [&::-webkit-details-marker]:hidden">
              {q}
              <span className="font-mono text-2xl text-ember transition-transform group-open:rotate-45">
                +
              </span>
            </summary>
            <p className="max-w-[760px] pb-6 text-lg text-paper/75 leading-relaxed">
              {a}
            </p>
          </details>
        ))}
      </div>
    </section>
  );
}

/* ---------- final CTA + footer ---------- */

function FinalCta() {
  return (
    <section
      id="download"
      className="flex scroll-mt-24 flex-col items-center px-6 py-32 text-center"
    >
      <Pixels rows={HAT} size={12} />
      <h2 className="mt-12 font-medium text-[clamp(44px,6.4vw,92px)] leading-[0.98] tracking-[-0.04em]">
        Ask better questions
        <br />
        <span className="text-ember">before you act.</span>
      </h2>
      <div className="mt-10 flex flex-wrap justify-center gap-3">
        <Btn href={DOWNLOAD_URL} primary>
          ↓ Download for macOS
        </Btn>
        <Btn href={GITHUB_URL}>★ Star on GitHub</Btn>
      </div>
      <InstallCommand className="mt-6 w-full max-w-[520px]" />
      <p className="mt-5 max-w-[520px] font-mono text-muted text-xs leading-5">
        The .dmg isn't signed with a paid Apple developer account, so macOS
        blocks it once: open it, then System Settings › Privacy &amp; Security ›
        Open Anyway. The Terminal command skips that step, and the app updates
        itself after that.
      </p>
    </section>
  );
}

function Footer() {
  const cols: [string, [string, string][]][] = [
    [
      "PRODUCT",
      [
        ["Download", "#download"],
        ["Features", "#features"],
        ["Web viewer", "/view"],
        ["Changelog", CHANGELOG_URL],
      ],
    ],
    [
      "COMMUNITY",
      [
        ["GitHub", GITHUB_URL],
        ["Report an issue", ISSUES_URL],
      ],
    ],
    [
      "PROJECT",
      [
        ["Docs", DOCS_URL],
        ["Install guide", INSTALL_URL],
        [`License · ${LICENSE}`, `${GITHUB_URL}/blob/main/LICENSE`],
      ],
    ],
  ];
  return (
    <footer className="border-line border-t">
      <div className="mx-auto grid max-w-[1288px] gap-10 px-6 py-16 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <span className="flex items-center gap-3 font-mono font-semibold text-lg">
            <Pixels rows={HAT} size={2.2} /> sorcerer
          </span>
          <p className="mt-4 text-paper/75">
            Open source. Inspired by MiroFish.
          </p>
          <p className="mt-3 font-mono text-muted text-sm">
            <span className="text-ember">●</span> everything local
          </p>
        </div>
        {cols.map(([title, items]) => (
          <div key={title}>
            <p className="font-mono text-muted text-xs tracking-widest">
              {title}
            </p>
            <ul className="mt-4 flex flex-col gap-3">
              {items.map(([label, href]) => (
                <li key={label}>
                  <a href={href} className="text-paper/85 hover:text-ember">
                    {label}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </footer>
  );
}
