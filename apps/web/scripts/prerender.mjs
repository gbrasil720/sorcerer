// Puts the landing's HTML inside #app so crawlers that don't run JavaScript
// (search and AI bots) read the real page instead of an empty div.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { render } from "../.ssr/prerender.js";

// Pixel art is thousands of <rect>s with no text in it; bots don't need it and
// React draws it on load.
const page = render().replace(/<svg[\s\S]*?<\/svg>/g, "");

const file = "dist/index.html";
const html = await readFile(file, "utf8");

// The viewer gets its own empty shell (no landing HTML to flash before React loads).
const view = html
  .replace(
    /<title>[^<]*<\/title>/,
    "<title>Sorcerer viewer: open a shared experiment</title>",
  )
  .replace(
    /(<meta\s+name="description"\s+content=")[^"]*"/,
    '$1Open a Sorcerer experiment (.sorcerer.json) in your browser: the feed round by round, polls, actions, characters and the report. Nothing is uploaded."',
  )
  .replace(
    'href="https://sorcererapp.dev/"',
    'href="https://sorcererapp.dev/view"',
  );
await mkdir("dist/view", { recursive: true });
await writeFile("dist/view/index.html", view);
const out = html.replace('<div id="app"></div>', `<div id="app">${page}</div>`);
if (out === html)
  throw new Error(
    'prerender: <div id="app"></div> not found in dist/index.html',
  );
await writeFile(file, out);
console.log(
  `prerender: ${out.length - html.length} bytes of landing HTML injected`,
);
