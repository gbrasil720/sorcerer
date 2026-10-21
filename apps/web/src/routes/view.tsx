import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import {
  Avatar,
  HAT,
  type Look,
  Meter,
  Pixels,
  signed,
} from "@/components/pixels";

export const Route = createFileRoute("/view")({
  component: Viewer,
  validateSearch: (s: Record<string, unknown>): { url?: string } =>
    typeof s.url === "string" ? { url: s.url } : {},
});

const DOWNLOAD_URL =
  "https://github.com/gbrasil720/sorcerer/releases/latest/download/Sorcerer.dmg";
const EXAMPLE = "/examples/lumen.sorcerer.json";

/* ---------- the file format (what the app's "Share" writes) ---------- */

type Persona = {
  handle: string;
  role: string;
  bio?: string;
  traits?: Record<string, number>;
  interests?: string[];
  goals?: string[];
  mood?: number;
  ties?: Record<string, string> | null;
  insider?: boolean | null;
  look?: Look | null;
  joined?: number | null;
};
type Post = {
  id: string;
  round: number;
  author: string;
  replyTo?: string | null;
  text: string;
  mood: number;
  agree?: number | null;
  disagree?: number | null;
};
type Action = {
  id: string;
  round: number;
  who: string;
  act: string;
  why: string;
};
type Poll = {
  id: string;
  round: number;
  question: string;
  options: string[];
  answers: Record<string, { pick: string; why: string }>;
  open?: boolean;
};
type WorldEvent = { id: string; round: number; text: string };
type Branch = {
  id: string;
  name: string;
  parent?: string | null;
  label?: string | null;
  round: number;
  characters: Persona[];
  posts: Post[];
  events: WorldEvent[];
  moodByRound: number[];
  actions?: Action[] | null;
  polls?: Poll[] | null;
};
type Finding = string | { text: string; refs?: string[] };
type Report = {
  headline: string;
  divergence?: string | null;
  findings: Finding[];
  questions: string[];
  branches?:
    | {
        name: string;
        summary: string;
        metrics: { label: string; value: string }[];
      }[]
    | null;
};
type Fact = { text: string; source: string; audience: string };
type Experiment = {
  name: string;
  hypothesis: string;
  context: string;
  branches: Branch[];
  report?: Report | null;
  created?: number | string;
  community?: string | null;
  environment?: string | null;
  rounds?: number | null;
  brief?: { title: string; tagline: string; facts: Fact[] } | null;
};

/** Checks the shape and fills the arrays older files leave out; null if it isn't a Sorcerer file. */
function parse(data: unknown): Experiment | null {
  const e = data as Experiment;
  if (
    !e ||
    typeof e.hypothesis !== "string" ||
    !Array.isArray(e.branches) ||
    !e.branches.length ||
    !e.branches.every((b) => b && Array.isArray(b.characters))
  )
    return null;
  for (const b of e.branches) {
    b.posts ??= [];
    b.events ??= [];
    b.moodByRound ??= [];
  }
  e.context ??= "";
  return e;
}

/** The app saves dates as seconds since 2001 (Foundation's reference date). */
function createdAt(c: Experiment["created"]) {
  if (c == null) return null;
  const d =
    typeof c === "number" ? new Date((c + 978307200) * 1000) : new Date(c);
  return Number.isNaN(d.getTime()) ? null : d;
}

const findingText = (f: Finding) => (typeof f === "string" ? f : f.text);
const findingRefs = (f: Finding) =>
  typeof f === "string" ? [] : (f.refs ?? []);

/** "A5" → branch A's 5th post, the way report findings cite posts. */
function resolve(e: Experiment, ref: string) {
  const r = ref.toUpperCase().replace(/[[\] ]/g, "");
  const b = e.branches.find((x) => x.name === r[0]);
  const n = Number(r.slice(1));
  if (!b || !Number.isInteger(n) || n < 1 || n > b.posts.length) return null;
  return { branch: b, post: b.posts[n - 1], n };
}

/* ---------- page ---------- */

type Source = { exp: Experiment; from: string };

function Viewer() {
  const { url } = Route.useSearch();
  const navigate = Route.useNavigate();
  const [src, setSrc] = useState<Source | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    document.title = src
      ? `What if ${src.exp.hypothesis} · Sorcerer viewer`
      : "Sorcerer viewer: open a shared experiment";
  }, [src]);

  useEffect(() => {
    if (!url) return;
    let link: URL;
    try {
      link = new URL(url, window.location.href);
    } catch {
      setError("That link isn't a valid URL.");
      return;
    }
    if (link.protocol !== "https:" && link.protocol !== "http:") {
      setError("Only http and https links can be opened.");
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch(link)
      .then((r) => {
        if (!r.ok) throw new Error(`the server answered ${r.status}`);
        return r.text();
      })
      .then((text) => {
        if (cancelled) return;
        let exp: Experiment | null = null;
        try {
          exp = parse(JSON.parse(text));
        } catch {}
        if (exp)
          setSrc({
            exp,
            from:
              link.hostname === window.location.hostname
                ? "example"
                : link.hostname,
          });
        else setError("That link doesn't point to a Sorcerer experiment.");
      })
      .catch((err: Error) => {
        if (cancelled) return;
        // fetch only says "Failed to fetch" when the host blocks cross-origin reads.
        setError(
          err instanceof TypeError
            ? "Couldn't load that link. The host has to allow cross-origin requests; raw GitHub and gist links do."
            : `Couldn't load that link: ${err.message}.`,
        );
      })
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [url]);

  async function open(file: File) {
    setError(null);
    try {
      const exp = parse(JSON.parse(await file.text()));
      if (!exp) {
        setError(`${file.name} isn't a Sorcerer experiment.`);
        return;
      }
      if (url) navigate({ search: {} });
      setSrc({ exp, from: file.name });
    } catch {
      setError(`${file.name} isn't valid JSON.`);
    }
  }

  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: dropping a file anywhere is a shortcut; the file picker works by keyboard
    <div
      className="min-h-svh bg-ink font-display text-paper antialiased selection:bg-ember selection:text-ink"
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={(e) => {
        if (e.currentTarget === e.target) setDragging(false);
      }}
      onDrop={(e) => {
        e.preventDefault();
        setDragging(false);
        const f = e.dataTransfer.files[0];
        if (f) open(f);
      }}
    >
      <Header
        loaded={!!src}
        onClose={() => {
          setSrc(null);
          setError(null);
          if (url) navigate({ search: {} });
        }}
      />
      <main className="mx-auto max-w-[1288px] px-6 pb-24">
        {src ? (
          <ExperimentView exp={src.exp} from={src.from} />
        ) : (
          <Drop
            onFile={open}
            error={error}
            loading={loading}
            dragging={dragging}
          />
        )}
      </main>
      {dragging && src && (
        <div className="pointer-events-none fixed inset-4 z-50 grid place-items-center rounded-xl border-2 border-ember border-dashed bg-ink/80 font-mono text-ember">
          drop to open this experiment instead
        </div>
      )}
    </div>
  );
}

function Header({ loaded, onClose }: { loaded: boolean; onClose: () => void }) {
  return (
    <header className="sticky top-0 z-40 border-line border-b bg-ink/85 backdrop-blur">
      <nav className="mx-auto flex h-[66px] max-w-[1288px] items-center justify-between gap-6 px-6">
        <div className="flex items-center gap-3">
          <Link to="/" className="flex items-center gap-3">
            <Pixels rows={HAT} size={2.2} />
            <span className="font-mono font-semibold text-lg">sorcerer</span>
          </Link>
          <span className="font-mono text-muted text-sm">/ viewer</span>
        </div>
        <div className="flex items-center gap-2.5">
          {loaded && (
            <button
              type="button"
              onClick={onClose}
              className="hidden h-10 items-center rounded-md border border-line px-4 font-mono text-sm hover:border-paper/40 sm:inline-flex"
            >
              open another
            </button>
          )}
          <a
            href={DOWNLOAD_URL}
            className="inline-flex h-10 items-center rounded-md bg-ember px-4 font-mono text-ink text-sm hover:bg-ember/90"
          >
            Get Sorcerer
          </a>
        </div>
      </nav>
    </header>
  );
}

function Drop({
  onFile,
  error,
  loading,
  dragging,
}: {
  onFile: (f: File) => void;
  error: string | null;
  loading: boolean;
  dragging: boolean;
}) {
  return (
    <section className="pt-20">
      <p className="font-mono text-ember text-sm">— viewer</p>
      <h1 className="mt-5 max-w-[820px] font-medium text-[clamp(40px,5.4vw,76px)] leading-[1.02] tracking-[-0.035em]">
        Open a shared experiment.
      </h1>
      <p className="mt-6 max-w-[620px] text-[20px] text-paper/75 leading-snug">
        Read someone's Sorcerer run without installing anything: the feed round
        by round, polls, actions, the characters and the report.
      </p>
      <label
        className={`mt-12 flex cursor-pointer flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed px-6 py-16 text-center transition-colors ${
          dragging
            ? "border-ember bg-ember/5"
            : "border-line hover:border-paper/40"
        }`}
      >
        <input
          type="file"
          accept=".json,application/json"
          className="sr-only"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) onFile(f);
            e.target.value = "";
          }}
        />
        <span className="font-mono text-lg">
          {loading
            ? "loading…"
            : dragging
              ? "drop it"
              : "drop a .sorcerer.json here, or choose a file"}
        </span>
        <span className="font-mono text-muted text-sm">
          it opens in your browser · nothing is uploaded
        </span>
      </label>
      {error && (
        <p role="alert" className="mt-4 font-mono text-ember text-sm">
          {error}
        </p>
      )}
      <div className="mt-10 grid gap-6 font-mono text-muted text-sm leading-6 md:grid-cols-3">
        <p>
          <span className="text-paper">No file?</span>{" "}
          <Link
            to="/view"
            search={{ url: EXAMPLE }}
            className="text-ember underline"
          >
            Open an example
          </Link>
          : six Lumen users react to a price rise, with a poll and actions.
        </p>
        <p>
          <span className="text-paper">Where files come from:</span> in
          Sorcerer, Experiment → Export Experiment… saves a run with its
          history; Share Bundle… saves a fresh setup for others to run.
        </p>
        <p>
          <span className="text-paper">Share a link:</span> put the file in a
          GitHub gist and send{" "}
          <span className="break-all text-paper/85">
            sorcererapp.dev/view?url=&lt;raw link&gt;
          </span>
        </p>
      </div>
    </section>
  );
}

/* ---------- an experiment ---------- */

type Tab = "feed" | "people" | "report" | "context";

function ExperimentView({ exp, from }: { exp: Experiment; from: string }) {
  const [branchName, setBranchName] = useState(exp.branches[0].name);
  const [tab, setTab] = useState<Tab>(exp.report ? "report" : "feed");
  const [focus, setFocus] = useState<string | null>(null);
  const b = exp.branches.find((x) => x.name === branchName) ?? exp.branches[0];
  const date = createdAt(exp.created);
  const fresh = exp.branches.every((x) => !x.posts.length);

  // Jump from a report citation to the post in the feed.
  useEffect(() => {
    if (!focus || tab !== "feed") return;
    document
      .getElementById(`post-${focus}`)
      ?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [focus, tab]);

  const tabs: [Tab, string][] = [
    ["feed", "feed"],
    ["people", `people · ${b.characters.length}`],
    ...(exp.report ? [["report", "report"] as [Tab, string]] : []),
    ["context", "context"],
  ];

  return (
    <article className="pt-14">
      <p className="flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-muted text-sm">
        <span className="text-ember">●</span>
        {[
          exp.community,
          exp.environment,
          `${b.characters.length} characters`,
          `${Math.max(...exp.branches.map((x) => x.round))} rounds`,
          exp.branches.length > 1 ? `${exp.branches.length} branches` : null,
          date?.toLocaleDateString(undefined, { dateStyle: "medium" }),
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
      <h1 className="mt-6 max-w-[1000px] font-medium text-[clamp(34px,4.6vw,64px)] leading-[1.04] tracking-[-0.035em]">
        What if <span className="text-ember">{exp.hypothesis}</span>
      </h1>
      <p className="mt-4 font-mono text-dim text-xs">
        from {from} · simulated with Sorcerer: hypotheses to explore, not
        evidence
      </p>

      <div className="sticky top-[66px] z-30 mt-10 flex flex-wrap items-center justify-between gap-4 border-line border-b bg-ink/90 py-3 backdrop-blur">
        <div role="tablist" className="flex gap-1 font-mono text-sm">
          {tabs.map(([t, label]) => (
            <button
              key={t}
              type="button"
              role="tab"
              aria-selected={tab === t}
              onClick={() => setTab(t)}
              className={`rounded-md px-3 py-1.5 transition-colors ${
                tab === t
                  ? "bg-panel text-paper"
                  : "text-muted hover:text-paper"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        {exp.branches.length > 1 && (tab === "feed" || tab === "people") && (
          <div className="flex gap-1 font-mono text-sm">
            {exp.branches.map((x) => (
              <button
                key={x.name}
                type="button"
                onClick={() => setBranchName(x.name)}
                className={`rounded-md border px-3 py-1.5 transition-colors ${
                  x.name === b.name
                    ? "border-ember text-paper"
                    : "border-line text-muted hover:text-paper"
                }`}
              >
                <span className="text-ember">{x.name}</span>
                {x.label ? ` · ${x.label}` : ""}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="mt-8">
        {tab === "feed" && (fresh ? <Fresh /> : <Feed b={b} focus={focus} />)}
        {tab === "people" && <People b={b} />}
        {tab === "report" && exp.report && (
          <ReportView
            exp={exp}
            report={exp.report}
            onRef={(ref) => {
              const hit = resolve(exp, ref);
              if (!hit) return;
              setBranchName(hit.branch.name);
              setFocus(`${hit.branch.name}${hit.n}`);
              setTab("feed");
            }}
          />
        )}
        {tab === "context" && <Context exp={exp} />}
      </div>
    </article>
  );
}

function Fresh() {
  return (
    <div className="rounded-xl border border-line border-dashed bg-panel px-6 py-14 text-center">
      <p className="text-2xl">A fresh scenario: nobody has spoken yet.</p>
      <p className="mx-auto mt-3 max-w-[520px] text-paper/70">
        Someone shared the setup so you can run it yourself. Open this file in
        Sorcerer and press run to see what your version of the world does.
      </p>
      <a
        href={DOWNLOAD_URL}
        className="mt-8 inline-flex h-11 items-center rounded-md bg-ember px-5 font-mono text-ink text-sm hover:bg-ember/90"
      >
        ↓ Download Sorcerer for macOS
      </a>
    </div>
  );
}

/* ---------- feed ---------- */

function Feed({ b, focus }: { b: Branch; focus: string | null }) {
  const people = new Map(b.characters.map((p) => [p.handle, p]));
  const number = new Map(b.posts.map((p, i) => [p.id, `${b.name}${i + 1}`]));
  // A public poll's event lands on the next round, which may not have run yet.
  const last = Math.max(b.round, ...b.events.map((x) => x.round));
  const rounds = Array.from({ length: last }, (_, i) => i + 1);

  return (
    <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_320px]">
      <div className="flex flex-col gap-10">
        {rounds.map((r) => {
          const events = b.events.filter((x) => x.round === r);
          const posts = b.posts.filter((x) => x.round === r);
          const actions = (b.actions ?? []).filter((x) => x.round === r);
          const polls = (b.polls ?? []).filter((x) => x.round === r);
          if (
            !events.length &&
            !posts.length &&
            !actions.length &&
            !polls.length
          )
            return null;
          return (
            <section key={r} aria-label={`Round ${r}`}>
              <div className="mb-4 flex items-center gap-3 font-mono text-muted text-xs tracking-widest">
                ROUND {r}
                <span className="h-px flex-1 bg-line" />
                {b.moodByRound[r] != null && (
                  <span>mood {signed(b.moodByRound[r])}</span>
                )}
              </div>
              <div className="flex flex-col gap-3">
                {events.map((x) => (
                  <p
                    key={x.id}
                    className="rounded-lg border border-ember/40 bg-ember/5 px-4 py-3 font-mono text-sm"
                  >
                    <span className="text-ember">⚡ event · </span>
                    {x.text}
                  </p>
                ))}
                {posts.map((p) => {
                  const n = number.get(p.id) ?? "";
                  return (
                    <PostCard
                      key={p.id}
                      p={p}
                      n={n}
                      who={people.get(p.author)}
                      lit={focus === n}
                    />
                  );
                })}
                {actions.map((a) => (
                  <p
                    key={a.id}
                    className="flex items-start gap-3 px-1 font-mono text-sm"
                  >
                    <Avatar
                      name={a.who}
                      look={people.get(a.who)?.look}
                      size={20}
                      className="mt-0.5"
                    />
                    <span>
                      <span className="text-paper">@{a.who}</span>{" "}
                      <span className="text-ember">→ {a.act}</span>
                      {a.why && <span className="text-muted"> · {a.why}</span>}
                    </span>
                  </p>
                ))}
                {polls.map((x) => (
                  <PollCard key={x.id} poll={x} people={people} />
                ))}
              </div>
            </section>
          );
        })}
      </div>
      <aside className="flex flex-col gap-6 lg:sticky lg:top-[140px] lg:self-start">
        <MoodChart b={b} />
        <Tally b={b} />
      </aside>
    </div>
  );
}

function PostCard({
  p,
  n,
  who,
  lit,
}: {
  p: Post;
  n: string;
  who?: Persona;
  lit: boolean;
}) {
  return (
    <div
      id={`post-${n}`}
      className={`flex gap-3 rounded-lg border bg-panel p-4 transition-colors ${
        lit ? "border-ember" : "border-line"
      }`}
    >
      <Avatar name={p.author} look={who?.look} size={36} />
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-baseline gap-x-2 font-mono text-sm">
          <span className="text-paper">@{p.author}</span>
          {who?.role && <span className="text-muted">{who.role}</span>}
          {p.replyTo && <span className="text-dim">↳ @{p.replyTo}</span>}
          <span className="ml-auto text-dim text-xs">{n}</span>
        </p>
        <p className="mt-1.5 text-[17px] leading-snug">{p.text}</p>
        <p className="mt-2 flex gap-4 font-mono text-muted text-xs">
          <span className={p.mood < 0 ? "text-ember" : ""}>
            mood {signed(p.mood)}
          </span>
          {p.agree != null && <span>▲ {p.agree}</span>}
          {p.disagree != null && <span>▼ {p.disagree}</span>}
        </p>
      </div>
    </div>
  );
}

function PollCard({
  poll,
  people,
}: {
  poll: Poll;
  people: Map<string, Persona>;
}) {
  const answers = Object.entries(poll.answers ?? {});
  const total = answers.length || 1;
  return (
    <div className="rounded-lg border border-line bg-panel p-4">
      <p className="font-mono text-muted text-xs">
        ? poll · asked everyone after this round
        {poll.open ? " · public" : " · off the record"}
      </p>
      <p className="mt-2 text-lg">{poll.question}</p>
      <div className="mt-4 flex flex-col gap-2 font-mono text-sm">
        {poll.options.map((o) => {
          const c = answers.filter(([, a]) => a.pick === o).length;
          return (
            <div key={o} className="flex items-center gap-3">
              <span className="w-28 shrink-0 truncate">{o}</span>
              <Meter value={c / total} cells={20} warn />
              <span className="text-muted">{c}</span>
            </div>
          );
        })}
      </div>
      {answers.length > 0 && (
        <details className="mt-4 font-mono text-sm">
          <summary className="cursor-pointer text-muted hover:text-paper">
            {answers.length} answers
          </summary>
          <ul className="mt-3 flex flex-col gap-2">
            {answers.map(([h, a]) => (
              <li key={h} className="flex items-start gap-3">
                <Avatar
                  name={h}
                  look={people.get(h)?.look}
                  size={20}
                  className="mt-0.5"
                />
                <span>
                  <span className="text-paper">@{h}</span>{" "}
                  <span className="text-ember">{a.pick}</span>
                  <span className="text-muted"> · {a.why}</span>
                </span>
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}

function MoodChart({ b }: { b: Branch }) {
  const m = b.moodByRound;
  if (m.length < 2) return null;
  const w = 288;
  const h = 96;
  const x = (i: number) => (i / (m.length - 1)) * w;
  const y = (v: number) => ((1 - v) / 2) * h;
  return (
    <div className="rounded-lg border border-line bg-panel p-4">
      <p className="flex justify-between font-mono text-muted text-xs">
        <span>community mood</span>
        <span>{signed(m[m.length - 1])}</span>
      </p>
      <svg
        viewBox={`0 0 ${w} ${h}`}
        className="mt-3 w-full"
        role="img"
        aria-label={`Mood by round: ${m.map((v) => v.toFixed(1)).join(", ")}`}
      >
        <line
          x1={0}
          x2={w}
          y1={h / 2}
          y2={h / 2}
          stroke="var(--color-line)"
          strokeDasharray="3 3"
        />
        <polyline
          fill="none"
          stroke="var(--color-ember)"
          strokeWidth={2}
          points={m.map((v, i) => `${x(i)},${y(v)}`).join(" ")}
        />
        {m.map((v, i) => (
          <circle
            key={i}
            cx={x(i)}
            cy={y(v)}
            r={2.5}
            fill="var(--color-paper)"
          />
        ))}
      </svg>
      <p className="mt-1 flex justify-between font-mono text-[11px] text-dim">
        <span>start</span>
        <span>round {m.length - 1}</span>
      </p>
    </div>
  );
}

function Tally({ b }: { b: Branch }) {
  const counts = new Map<string, number>();
  for (const a of b.actions ?? [])
    counts.set(a.act, (counts.get(a.act) ?? 0) + 1);
  if (!counts.size) return null;
  const max = Math.max(...counts.values());
  return (
    <div className="rounded-lg border border-line bg-panel p-4">
      <p className="font-mono text-muted text-xs">what people did</p>
      <ul className="mt-3 flex flex-col gap-2 font-mono text-sm">
        {[...counts]
          .sort((a, z) => z[1] - a[1])
          .map(([act, c]) => (
            <li key={act} className="flex items-center justify-between gap-3">
              <span className="truncate">{act}</span>
              <span className="flex items-center gap-2 text-muted">
                <Meter value={c / max} cells={8} />
                {c}
              </span>
            </li>
          ))}
      </ul>
    </div>
  );
}

/* ---------- people ---------- */

function People({ b }: { b: Branch }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {b.characters.map((p) => (
        <div
          key={p.handle}
          className="rounded-lg border border-line bg-panel p-5"
        >
          <div className="flex items-center gap-4">
            <Avatar name={p.handle} look={p.look} size={56} />
            <div className="min-w-0">
              <p className="font-mono">@{p.handle}</p>
              <p className="text-muted text-sm">{p.role}</p>
              {(p.insider || p.joined != null) && (
                <p className="mt-1 flex gap-2 font-mono text-[11px] text-ember">
                  {p.insider && <span>insider</span>}
                  {p.joined != null && <span>joined r{p.joined}</span>}
                </p>
              )}
            </div>
          </div>
          {p.bio && (
            <p className="mt-4 text-paper/80 text-sm leading-snug">{p.bio}</p>
          )}
          <div className="mt-4 flex flex-col gap-1.5 font-mono text-xs">
            <Row label="mood">
              <Meter
                value={((p.mood ?? 0) + 1) / 2}
                cells={12}
                warn={(p.mood ?? 0) < 0}
              />
              <span className="text-muted">{signed(p.mood ?? 0)}</span>
            </Row>
            {Object.entries(p.traits ?? {}).map(([t, v]) => (
              <Row key={t} label={t}>
                <Meter value={v} cells={12} />
              </Row>
            ))}
          </div>
          {!!p.interests?.length && (
            <p className="mt-4 flex flex-wrap gap-1.5 font-mono text-[11px]">
              {p.interests.map((i) => (
                <span
                  key={i}
                  className="rounded border border-line px-1.5 py-0.5 text-muted"
                >
                  {i}
                </span>
              ))}
            </p>
          )}
          {!!p.goals?.length && (
            <ul className="mt-3 flex flex-col gap-1 text-paper/75 text-sm">
              {p.goals.map((g) => (
                <li key={g}>· {g}</li>
              ))}
            </ul>
          )}
          {p.ties && Object.keys(p.ties).length > 0 && (
            <p className="mt-3 font-mono text-muted text-xs leading-5">
              {Object.entries(p.ties)
                .map(([h, rel]) => `@${h} ${rel}`)
                .join(" · ")}
            </p>
          )}
        </div>
      ))}
    </div>
  );
}

const Row = ({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) => (
  <div className="flex items-center gap-3">
    <span className="w-24 shrink-0 truncate text-muted">{label}</span>
    {children}
  </div>
);

/* ---------- report & context ---------- */

function ReportView({
  exp,
  report,
  onRef,
}: {
  exp: Experiment;
  report: Report;
  onRef: (ref: string) => void;
}) {
  return (
    <div className="max-w-[880px]">
      <p className="text-[clamp(24px,2.6vw,34px)] leading-tight tracking-[-0.02em]">
        {report.headline}
      </p>
      {!!report.branches?.length && (
        <div className="mt-8 grid gap-4 sm:grid-cols-2">
          {report.branches.map((s) => (
            <div
              key={s.name}
              className="rounded-lg border border-line bg-panel p-5"
            >
              <p className="font-mono text-sm">
                <span className="text-ember">{s.name}</span> · {s.summary}
              </p>
              <dl className="mt-4 flex flex-col gap-2 text-sm">
                {s.metrics.map((m) => (
                  <div key={m.label} className="flex justify-between gap-4">
                    <dt className="text-muted">{m.label}</dt>
                    <dd className="text-right font-mono">{m.value}</dd>
                  </div>
                ))}
              </dl>
            </div>
          ))}
        </div>
      )}
      {report.divergence && (
        <>
          <H3>where the branches diverged</H3>
          <p className="text-paper/85 leading-relaxed">{report.divergence}</p>
        </>
      )}
      <H3>findings</H3>
      <ol className="flex flex-col gap-5">
        {report.findings.map((f, i) => (
          <li key={i} className="flex gap-4">
            <span className="font-mono text-ember">{i + 1}</span>
            <div>
              <p className="leading-relaxed">{findingText(f)}</p>
              <div className="mt-2 flex flex-col gap-1.5">
                {findingRefs(f).map((ref) => {
                  const hit = resolve(exp, ref);
                  if (!hit) return null;
                  return (
                    <button
                      key={ref}
                      type="button"
                      onClick={() => onRef(ref)}
                      className="text-left font-mono text-muted text-xs hover:text-paper"
                    >
                      <span className="text-ember">{ref.toUpperCase()}</span> ·
                      r{hit.post.round} · @{hit.post.author}: “{hit.post.text}”
                    </button>
                  );
                })}
              </div>
            </div>
          </li>
        ))}
      </ol>
      {report.questions.length > 0 && (
        <>
          <H3>questions to investigate</H3>
          <ul className="flex flex-col gap-2">
            {report.questions.map((q) => (
              <li key={q} className="text-paper/85">
                <span className="text-ember">? </span>
                {q}
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

const H3 = ({ children }: { children: string }) => (
  <h2 className="mt-12 mb-4 font-mono text-muted text-xs uppercase tracking-widest">
    {children}
  </h2>
);

function Context({ exp }: { exp: Experiment }) {
  return (
    <div className="max-w-[880px]">
      {exp.brief && (
        <>
          <p className="text-2xl">{exp.brief.title}</p>
          <p className="mt-1 text-muted">{exp.brief.tagline}</p>
          <ul className="mt-6 flex flex-col gap-2">
            {exp.brief.facts.map((f) => (
              <li key={f.text} className="flex gap-3 text-sm">
                <span className="w-16 shrink-0 font-mono text-ember text-xs">
                  {f.audience === "public" ? "public" : f.audience}
                </span>
                <span className="text-paper/85">{f.text}</span>
              </li>
            ))}
          </ul>
          <H3>the full context</H3>
        </>
      )}
      <pre className="whitespace-pre-wrap rounded-lg border border-line bg-panel p-5 font-mono text-paper/85 text-sm leading-6">
        {exp.context || "No context was given."}
      </pre>
    </div>
  );
}
