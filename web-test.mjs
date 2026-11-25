// ===================================================================
// web-test.mjs — the built page, driven the way a browser would.
// ===================================================================
// The page runs the compiled game: its answers come from the
// bundled bend code, and its own hands (SVG, pointer, clock) answer
// to nothing but the DOM. This test loads freecell.html — the very
// artifact that ships — into jsdom and plays it: renders, moves,
// undo, safe sends, the win, the search, the paint order of every
// column, and the share-by-link behavior of the address bar.
//
// It builds the page first, so it always tests what would ship:
//
//   npm install     # once: jsdom
//   node web-test.mjs
//
// jsdom runs no ES modules, so the page's one inline module script
// is flipped to a classic script — the bundle has no imports or
// exports of its own, so the code runs identically either way.

import {JSDOM} from "jsdom";
import {readFileSync} from "fs";
import {execFileSync} from "child_process";
import {fileURLToPath} from "url";
import path from "path";

const root = path.dirname(fileURLToPath(import.meta.url));
const PAGE = "https://freecell.example/freecell.html";

console.log("building the page…");
execFileSync("sh", [path.join(root, "build-web.sh")], {cwd: root, stdio: "inherit"});

const html = readFileSync(path.join(root, "freecell.html"), "utf8")
  .replace('<script type="module">', "<script>");

const dom = new JSDOM(html, {url: PAGE, runScripts: "dangerously", pretendToBeVisual: true});
const {window} = dom;
const doc = window.document;

let failures = 0;
const ok = (name, cond) => {
  console.log((cond ? "ok   " : "FAIL ") + name);
  if (!cond) failures++;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// bend value builders
const Nil = {$: "Nil"};
const Con = (h, t) => ({$: "Con", head: h, tail: t});
const list = (a) => a.reduceRight((t, h) => Con(h, t), Nil);
const Card = (s, r) => ({$: "Card", suit: {$: s}, rank: {$: r}});
const Board = (cascades, cells, founds) => ({$: "Board",
  cascades: list(cascades.map((p) => list(p))),
  cells: list(cells.map((c) => (c ? {$: "Some", value: c} : {$: "None"}))),
  founds: list(founds)});

await sleep(15);

const fc = window.freecell;
ok("window.freecell exposed", !!fc);
ok("52 cards on the table", doc.querySelectorAll(".card").length === 52);
ok("16 slot outlines", doc.querySelectorAll(".slot").length === 16);

// paint order within a column: DOM order must run bottom-up, so the
// top card is painted last and covers the cards it buries. Positions
// live in dataset, so the check reads them the same way in any layer.
const paintOrder = (x) => {
  const col = [...doc.querySelectorAll("#table .card")]
    .map((el, pos) => ({x: +el.dataset.x, y: +el.dataset.y, pos}))
    .filter((c) => c.x === x && c.y >= 180);
  col.sort((a, b) => a.pos - b.pos);
  return col.map((c) => c.y);
};
const bottomUp = (ys) => ys.length > 0 && ys[0] === 180 && ys.every((y, i) => i === 0 || y > ys[i - 1]);
await sleep(320); // the first render's flights settle
{
  const ys = paintOrder(12.5);   // column 0's cascade
  ok("cascade paint order runs bottom-up", bottomUp(ys));
  ok("the resting layer holds all 52", doc.querySelectorAll("#cards .card").length === 52);
  ok("the flights layer is empty at rest", doc.getElementById("flights").children.length === 0);
}
// both corner indices: the top-left, and its upside-down twin
{
  const first = doc.querySelector(".card");
  const idx = first.querySelectorAll(".idx");
  ok("both corners carry the rank and suit", idx.length === 2);
  ok("the second corner is rotated", /rotate\(180 /.test(idx[1].getAttribute("transform") || ""));
  ok("104 corner labels on the table", doc.querySelectorAll(".idx").length === 104);
}
// the big suit glyph sits at the card's center
ok("the big suit glyph is centered", doc.querySelector(".card .pip").getAttribute("y") === "86");

// the page opens on a random game from the classic range — never the
// unsolvable 11982 — and the deal box and the address name it
ok("opens on a random game in the classic range",
   fc.game.no >= 1 && fc.game.no <= 32000 && fc.game.no !== 11982);
ok("the deal box names the game", +doc.getElementById("gameno").value === fc.game.no);
ok("the address names the game", window.location.hash === "#" + fc.game.no);
// the deterministic tests below want a known deal
fc.newGame(1);
ok("the address follows the deal", window.location.hash === "#1");
ok("status chrome", doc.getElementById("gameline").textContent.includes("game 1"));

// an illegal move is refused by the rules
const before = fc.game.board;
ok("illegal move refused", fc.play({$: "CascadeToFoundation", col: 0}) === false);
ok("board unchanged by refusal", fc.game.board === before);
ok("no moves counted", fc.game.moves === 0);

// a legal move exists on game 1; find one through the rules
// (a top card always fits a free cell, so scan those first)
const M = {
  cascadeToCell: (col, cell) => ({$: "CascadeToCell", col, cell}),
  cascadeToCascade: (col, col2) => ({$: "CascadeToCascade", col, col2}),
  cascadeToFoundation: (col) => ({$: "CascadeToFoundation", col}),
  cellToCascade: (cell, col) => ({$: "CellToCascade", cell, col}),
  cellToFoundation: (cell) => ({$: "CellToFoundation", cell}),
};
let legal = null;
for (let c = 0; c < 8 && !legal; c++) for (let t = 0; t < 8 && !legal; t++) {
  const cand = c === t ? M.cascadeToCell(c, 0) : M.cascadeToCascade(c, t);
  if (fc.F.canMove(fc.game.board, cand) === true) legal = cand;
}
ok("a legal cascade move exists on game 1", !!legal);
ok("legal move played", fc.play(legal) === true);
ok("moves counted", fc.game.moves === 1);
ok("undo stack grew", fc.game.past.length === 1);
fc.undo();
ok("undo takes it back", fc.game.moves === 0);
fc.redo();
ok("redo replays it", fc.game.moves === 1);

// board surgery: the ace of spades on top of column 0
const asTop = Board([[Card("Spades", "Ace")], [], [], [], [], [], [], []], [null, null, null, null], [0, 0, 0, 0]);
fc.game.board = asTop;
fc.render();
fc.safeMoves();
const founds = (b) => { const a = []; let l = b.founds; while (l.$ === "Con") { a.push(l.head); l = l.tail; } return a; };
ok("safe moves send the ace home", JSON.stringify(founds(fc.game.board)) === "[1,0,0,0]");
ok("autoplay move counted", fc.game.moves === 2); // 1 (redo) + 1 (ace home)
fc.undo();
ok("undo restores the ace to the column", founds(fc.game.board)[0] === 0);

// the clock runs from the deal, and pause holds it and hides the cards
await sleep(600);
ok("clock is ticking", /^\d+:[0-5]\d$/.test(doc.getElementById("clock").textContent));
doc.getElementById("pause").click();
ok("paused hides the cards", doc.getElementById("table").classList.contains("paused"));
ok("paused shows the veil", doc.getElementById("veil").classList.contains("on"));
const held = doc.getElementById("clock").textContent;
await sleep(600);
ok("clock holds while paused", doc.getElementById("clock").textContent === held);
{
  const frozen = JSON.stringify(founds(fc.game.board));
  fc.safeMoves(); // must be refused while paused
  ok("moves are refused while paused", JSON.stringify(founds(fc.game.board)) === frozen);
}
doc.getElementById("pause").click();
ok("resume unpauses", !doc.getElementById("table").classList.contains("paused"));

// a won board shows the banner
fc.game.board = Board([[], [], [], [], [], [], [], []], [null, null, null, null], [13, 13, 13, 13]);
fc.render();
ok("win banner shows", doc.getElementById("banner").classList.contains("on"));

// the search, a few levels deep, on a fresh game 1
doc.getElementById("banner").classList.remove("on");
await fc.newGame(1);
await fc.solve(8); // the UI's own entry, with a small budget…
ok("search ends within its budget", fc.game.solving === false);
ok("small budget says no solution", doc.getElementById("status").textContent.includes("no solution"));
ok("progress bar hidden again", !doc.getElementById("solvebar").classList.contains("on"));

// a redeal settles every card into its column's paint order
await fc.newGame(2);
await sleep(320);
ok("paint order settles after a redeal", bottomUp(paintOrder(12.5)));

// the reported bug: a card that lands exactly where it already was
// must still end up on top of its own column. Board A: the king of
// hearts tops a column holding the ace under it. Board B: the queen
// takes the ace's place — every card moves but the king.
{
  const KH = Card("Hearts", "King"), QH = Card("Hearts", "Queen"), AS = Card("Spades", "Ace");
  const others = [];
  for (const s of ["Spades", "Hearts", "Diamonds", "Clubs"])
    for (const r of ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                     "Nine", "Ten", "Jack", "Queen", "King"])
      if (!(s === "Hearts" && (r === "King" || r === "Queen")) && !(s === "Spades" && r === "Ace"))
        others.push(Card(s, r));
  fc.game.board = Board([others, [QH], [], [], [], [], [], [KH, AS]], [null, null, null, null], [0, 0, 0, 0]);
  fc.render();
  await sleep(320);
  fc.game.board = Board([[AS, ...others], [], [], [], [], [], [], [KH, QH]], [null, null, null, null], [0, 0, 0, 0]);
  fc.render();
  // two cards land exactly where they already were: the king, which
  // tops its column, and the deepest card of column 0. The other
  // fifty ride the top layer mid-flight — where re-appending cannot
  // touch them — then settle into place
  ok("flying cards ride the top layer", doc.getElementById("flights").children.length === 50);
  await sleep(320);
  ok("flights land back in the resting layer",
     doc.getElementById("flights").children.length === 0 &&
     doc.querySelectorAll("#cards .card").length === 52);
  const ys = paintOrder(887.5); // column 7: the queen at 180, the king at 212
  ok("a top card that stayed put still paints on top of its column",
     ys.length === 2 && ys[0] === 180 && ys[1] === 212);
  ok("a bottom card that stayed put still paints first in its column", paintOrder(12.5)[0] === 180);
}

// the stepping protocol, straight through the page's own module
const auto = fc.F.autoplay(64, fc.game.board);
let state = fc.F.first(auto, 200);
ok("search opens as a beam", state.$ === "Beam" && state.level === 200);
state = fc.F.step(state);
state = fc.F.step(state);
ok("two levels spent", state.$ === "Beam" && state.level === 198);

// sharing: a link that names a game deals it, and a hash that names
// no game falls back to a random one — rewriting the address
{
  const shared = new JSDOM(html, {url: PAGE + "#42", runScripts: "dangerously", pretendToBeVisual: true});
  await sleep(15);
  ok("a link deals the game it names", shared.window.freecell.game.no === 42);
  ok("the link's hash stays put", shared.window.location.hash === "#42");

  const odd = new JSDOM(html, {url: PAGE + "#letsplay", runScripts: "dangerously", pretendToBeVisual: true});
  await sleep(15);
  const no = odd.window.freecell.game.no;
  ok("a hash that names no game falls back to a random one",
     no >= 1 && no <= 32000 && no !== 11982);
  ok("the address is rewritten to the game it dealt", odd.window.location.hash === "#" + no);

  const seeds = [];
  for (let i = 0; i < 4; i++) {
    const fresh = new JSDOM(html, {url: PAGE, runScripts: "dangerously", pretendToBeVisual: true});
    await sleep(15);
    seeds.push(fresh.window.freecell.game.no);
  }
  ok("fresh loads open different games", new Set(seeds).size === seeds.length);
}

console.log(failures === 0 ? "\nALL WEB TESTS PASS" : "\n" + failures + " FAILURES");
process.exit(failures === 0 ? 0 : 1);
