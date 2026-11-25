// ===================================================================
// solver-test.mjs — the page's search against the solver's own.
// ===================================================================
// The browser page cannot call the one-shot search: it takes ~19s
// in the JS target and would freeze the page. Instead it opens the
// search with Web.open and advances it one beam level at a time
// with Web.step, yielding between levels.
//
// This is the port, in HOW-TO-USE-BEND.md's sense: JS driving the
// checked search from outside. The discipline that document asks
// of a port is the differential test — same board into both paths,
// same winning line out, forever. This file is that test: the
// stepped line (Web.open/Web.step) and the one-shot line (Web.deep,
// the CLI solver's own path) for game 1 must agree, move for move.
//
//   node solver-test.mjs     (~40s: two full searches)
//
// It gates solver.bend changes, not every commit — the deep check,
// as the repo's own documents split the cheap gates from the deep
// ones. The Web.* keys are the stable API; no module paths live
// here, so this test survives a moved tree.

import {execFileSync} from "child_process";
import {mkdtempSync, rmSync} from "fs";
import {tmpdir} from "os";
import path from "path";
import {fileURLToPath, pathToFileURL} from "url";

const root = path.dirname(fileURLToPath(import.meta.url));

function findBend() {
  const cands = ["bend", path.join(process.env.HOME || "", ".bend", "bin", "bend")];
  for (const cmd of cands) {
    try { execFileSync(cmd, ["version"], {stdio: "ignore"}); return cmd; }
    catch { /* try the next place */ }
  }
  throw new Error("solver-test: bend not found (PATH or ~/.bend/bin)");
}

const dir = mkdtempSync(path.join(tmpdir(), "freecell-solver-test-"));
try {
  console.log("exporting web.bend…");
  const out = path.join(dir, "web.mjs");
  execFileSync(findBend(), [path.join(root, "web.bend"), "-o", out], {stdio: "inherit"});
  const W = (await import(pathToFileURL(out).href)).default;

  const deal = W["Web.deal"];
  const open = W["Web.open"];
  const step = W["Web.step"];
  const deep = W["Web.deep"];
  const moveWord = W["Web.move_word"];

  const board = deal(1);

  // the solver's own path: one call, run to its answer
  console.log("one-shot solve (the CLI solver's path)…");
  const t0 = performance.now();
  const direct = deep(200, board);
  const t1 = performance.now();

  // the page's path: open, then one level at a time
  console.log("stepped solve (the browser's path)…");
  let state = open(board, 200);
  let levels = 0;
  while (state.$ === "Beam") {
    state = step(state);
    levels++;
    if (levels > 300) break;
  }
  const t2 = performance.now();

  const toArr = (l) => { const a = []; while (l && l.$ === "Con") { a.push(l.head); l = l.tail; } return a; };
  const words = (line) => toArr(line).map(moveWord);

  console.log("one-shot:", direct.$, "in", ((t1 - t0) / 1000).toFixed(1) + "s");
  console.log("stepped: ", state.$, "after", levels, "levels in", ((t2 - t1) / 1000).toFixed(1) + "s");

  const a = words(direct.line), b = words(state.line);
  const same = JSON.stringify(a) === JSON.stringify(b);
  console.log("line lengths:", a.length, b.length);
  console.log("the lines agree, move for move:", same);

  // the hint, checked for judgment: a couple of levels deep, the
  // beam's chosen opener must be the winning line's own — the
  // shallow search and the whole solve open alike on game 1
  const opener = W["Web.opener"], hintLevels = W["Web.hint_levels"];
  let h = open(board, hintLevels());
  while (h.$ === "Beam" && h.level > 0) h = step(h);
  const picked = opener(h);
  const hintOpens = picked.$ === "Some" ? moveWord(picked.value) : "(nothing)";
  const agree = hintOpens === a[0];
  console.log("the hint opens with:", hintOpens, "— the line's own opener:", a[0], "— agree:", agree);

  const ok = same && agree;
  if (!same && a.length === b.length) {
    console.log("first divergence:", a.findIndex((w, i) => w !== b[i]));
  }
  process.exit(ok ? 0 : 1);
} finally {
  rmSync(dir, {recursive: true, force: true});
}
