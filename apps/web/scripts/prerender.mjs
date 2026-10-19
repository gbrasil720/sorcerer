// Puts the landing's HTML inside #app so crawlers that don't run JavaScript
// (search and AI bots) read the real page instead of an empty div.
import { readFile, writeFile } from "node:fs/promises";
import { render } from "../.ssr/prerender.js";

// Pixel art is thousands of <rect>s with no text in it; bots don't need it and
// React draws it on load.
const page = render().replace(/<svg[\s\S]*?<\/svg>/g, "");

const file = "dist/index.html";
const html = await readFile(file, "utf8");
const out = html.replace('<div id="app"></div>', `<div id="app">${page}</div>`);
if (out === html)
  throw new Error(
    'prerender: <div id="app"></div> not found in dist/index.html',
  );
await writeFile(file, out);
console.log(
  `prerender: ${out.length - html.length} bytes of landing HTML injected`,
);
