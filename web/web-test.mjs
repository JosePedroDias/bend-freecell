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
// every slot is a bay with a rim wider than a card, so a card
// parked on it — a loaded foundation, a tall column's base — can
// never bury the legal outline under the cards
{
  const face = +doc.querySelector(".card .face").getAttribute("width");
  const bays = [...doc.querySelectorAll(".slot")].map((el) => +el.getAttribute("width"));
  ok("every slot bays wider than a card", bays.length === 16 && bays.every((w) => w > face));
}
// the foundations read S H C D down the row — the colors
// alternating — every suit wearing its own
{
  const wms = [...doc.querySelectorAll(".wm")];
  const wears = (el) => el.classList.contains("blk") ? "blk" : el.classList.contains("red") ? "red" : "none";
  ok("the foundations alternate suits SHCD", wms.map((el) => el.textContent).join("") === "♠♥♣♦");
  ok("the watermarks alternate black red black red", wms.map(wears).join(" ") === "blk red blk red");
}

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

// the dimming rule, in the player's own examples: 6S-7H-8C (bottom
// to top) climbs — each card a place the one beneath it can hop
// onto — and is fully lit; 8C-7H-6S falls and only its working card
// stays lit. A column's working card, every ace, every
// foundation-ready card and every card of a rising run stay lit;
// cells and foundations never darken
{
  const dimmed = (k) => doc.querySelector(`[data-key="${k}"]`).classList.contains("dim");
  const setCol0 = (col) => {
    fc.game.board = Board([col, [], [], [], [], [], [], []], [null, null, null, null], [0, 0, 0, 0]);
    fc.render();
  };
  setCol0([Card("Spades", "Six"), Card("Hearts", "Seven"), Card("Clubs", "Eight")]); // 6S 7H 8C
  ok("a rising run is fully lit: its 6S", !dimmed("Spades-Six"));
  ok("a rising run is fully lit: its 7H", !dimmed("Hearts-Seven"));
  ok("a rising run is fully lit: its 8C", !dimmed("Clubs-Eight"));
  setCol0([Card("Clubs", "Eight"), Card("Hearts", "Seven"), Card("Spades", "Six")]); // 8C 7H 6S
  ok("a falling run keeps only its working card lit", !dimmed("Clubs-Eight"));
  ok("the 7H of a falling run is darkened", dimmed("Hearts-Seven"));
  ok("the 6S of a falling run is darkened", dimmed("Spades-Six"));
  // the rest of the rule, on one board (columns listed bottom to top)
  fc.game.board = Board(
    [
      [Card("Spades", "Nine"), Card("Hearts", "King"), Card("Clubs", "Three")], // working, misfit, misfit
      [Card("Clubs", "Six"), Card("Diamonds", "Seven")],                         // working, the club hops onto it
      [Card("Spades", "King"), Card("Hearts", "Ace"), Card("Clubs", "Five")],    // working, buried ace, misfit
      [Card("Clubs", "Nine"), Card("Spades", "Two")],                            // working, foundation-ready
      [], [], [], [],
    ],
    [Card("Diamonds", "Eight"), null, null, null],
    [1, 0, 0, 0]); // the ace of spades home, so its two is wanted next
  fc.render();
  ok("the working card, bottom-most on screen, stays lit", !dimmed("Spades-Nine"));
  ok("a buried misfit king is darkened", dimmed("Hearts-King"));
  ok("a misfit deeper in the column is darkened", dimmed("Clubs-Three"));
  ok("a card the one beneath can rest on stays lit", !dimmed("Diamonds-Seven"));
  ok("a buried ace stays lit", !dimmed("Hearts-Ace"));
  ok("a buried foundation-ready card stays lit", !dimmed("Spades-Two"));
  ok("another buried misfit is darkened", dimmed("Clubs-Five"));
  ok("a card in a cell is never darkened", !dimmed("Diamonds-Eight"));
  ok("a card at home is never darkened", !dimmed("Spades-Ace"));
  // the evaluation is redone after a move: take the working card
  // away, and the buried misfit beneath becomes the working card —
  // into the light; undo, and it darkens again
  ok("the working card moves to a cell", fc.play({$: "CascadeToCell", col: 0, cell: 1}) === true);
  ok("the new working card comes into the light", !dimmed("Hearts-King"));
  ok("the misfit above it stays darkened", dimmed("Clubs-Three"));
  fc.undo();
  ok("back in place, it is darkened again", dimmed("Hearts-King"));
}

// supermoves: a column's rising run crosses to another column as a
// sequence of single moves — parks, a landing, restacks — every
// one checked by the rules as it plays, and the whole crossing is
// one undo. With too few cells and no spare column, nothing moves
{
  const toJs = (l) => { const a = []; while (l && l.$ === "Con") { a.push(l.head); l = l.tail; } return a; };
  const head = (col) => { const pile = toJs(toJs(fc.game.board.cascades)[col]); return pile.length ? pile[0].suit.$ + "-" + pile[0].rank.$ : null; };
  const runBoard = Board(
    [[Card("Hearts", "Three"), Card("Spades", "Four"), Card("Diamonds", "Five")], // the climbing run
     [Card("Clubs", "Six")],                                                      // waiting to take it
     [], [], [], [], [], []],
    [null, null, null, null], [0, 0, 0, 0]);
  fc.game.board = runBoard;
  fc.render();
  ok("the run is grabbable to its top", +fc.F.grab(fc.game.board, 0) === 3);
  const got = fc.F.supermove(fc.game.board, 0, 2, 1);
  ok("the supermove expands", got.$ === "Some");
  const ms = toJs(got.value.moves);
  ok("three cards cross in five moves", ms.length === 5);
  ok("first the two parks", ms[0].$ === "CascadeToCell" && ms[1].$ === "CascadeToCell");
  ok("then the run's top card lands", ms[2].$ === "CascadeToCascade");
  ok("then the two restacks", ms[3].$ === "CellToCascade" && ms[4].$ === "CellToCascade");
  ok("a top the target refuses is refused", fc.F.supermove(fc.game.board, 0, 1, 1).$ === "None");
  // the UI path: five beats, one undo
  ok("the page plays the supermove", await fc.playSuper(0, 2, 1) === true);
  ok("five moves counted", fc.game.moves === 5);
  ok("the run sits on the six", head(1) === "Hearts-Three");
  ok("the source column is bare", head(0) === null);
  fc.undo();
  ok("one undo takes the whole run back", fc.game.moves === 0 && head(0) === "Hearts-Three");
  // staging: one free cell, spare empty columns
  fc.game.board = Board(
    [[Card("Hearts", "Three"), Card("Spades", "Four"), Card("Diamonds", "Five")],
     [Card("Clubs", "Six")], [], [], [], [], [], []],
    [Card("Spades", "Seven"), Card("Hearts", "Eight"), Card("Diamonds", "Nine"), null],
    [0, 0, 0, 0]);
  fc.render();
  ok("staged over a spare column", await fc.playSuper(0, 2, 1) === true);
  ok("the staged crossing also takes five moves", fc.game.moves === 5);
  const cells = toJs(fc.game.board.cells).map((c) => c.$ === "Some" ? c.value.rank.$ : null);
  ok("the cells end as they began", JSON.stringify(cells) === JSON.stringify(["Seven", "Eight", "Nine", null]));
  // no cells, no empties: even a willing target refuses
  fc.game.board = Board(
    [[Card("Hearts", "Three"), Card("Spades", "Four"), Card("Diamonds", "Five")],
     [Card("Clubs", "Six")],
     [Card("Spades", "Seven")], [Card("Hearts", "Eight")], [Card("Diamonds", "Nine")],
     [Card("Clubs", "Ten")], [Card("Spades", "Jack")], [Card("Hearts", "Queen")]],
    [Card("Clubs", "Ace"), Card("Diamonds", "Two"), Card("Clubs", "King"), Card("Diamonds", "Ace")],
    [0, 0, 0, 0]);
  fc.render();
  ok("no cells and no empties refuse the run", await fc.playSuper(0, 2, 1) === false);
  ok("nothing moved", fc.game.moves === 5 && head(0) === "Hearts-Three"); // 5 from the staged test, unchanged
}

// the foundations are a home, not a trap: the top card of a loaded
// foundation comes back down onto any column that takes it — one
// move, one undo — and only the top: the ace beneath stays home.
// An empty foundation gives nothing, and no column takes what it
// cannot stack
{
  const toJs = (l) => { const a = []; while (l && l.$ === "Con") { a.push(l.head); l = l.tail; } return a; };
  const head = (col) => { const pile = toJs(toJs(fc.game.board.cascades)[col]); return pile.length ? pile[0].suit.$ + "-" + pile[0].rank.$ : null; };
  const pull = (f, c) => ({$: "FoundationToCascade", found: f, col: c});
  fc.game.board = Board(
    [[Card("Hearts", "Ten")], [Card("Diamonds", "Jack")], [], [], [], [], [], []],
    [null, null, null, null], [2, 0, 0, 0]);   // the spade foundation: A♠ under 2♠
  fc.game.moves = 0; fc.game.past.length = 0; fc.game.future.length = 0;
  fc.render();
  ok("the pull is legal through the page's rules", fc.F.canMove(fc.game.board, pull(0, 2)) === true);
  ok("a column that cannot stack it refuses", fc.F.canMove(fc.game.board, pull(0, 0)) === false);
  ok("an empty foundation gives nothing", fc.F.canMove(fc.game.board, pull(1, 2)) === false);
  ok("the page plays the pull", fc.play(pull(0, 2)) === true);
  ok("the two of spades came down", head(2) === "Spades-Two");
  ok("the ace stayed home", JSON.stringify(toJs(fc.game.board.founds)) === "[1,0,0,0]");
  ok("the pull counted one move", fc.game.moves === 1);
  fc.undo();
  ok("one undo takes it home again", JSON.stringify(toJs(fc.game.board.founds)) === "[2,0,0,0]" && fc.game.moves === 0);
  // the undo emptied the column and reloaded the foundation
  ok("the pull is legal again after the undo", head(2) === null && fc.F.canMove(fc.game.board, pull(0, 2)) === true);
}

// the stepping protocol, straight through the page's own module
let state = fc.F.first(fc.game.board, 200);
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
