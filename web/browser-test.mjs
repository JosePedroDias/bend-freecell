// ===================================================================
// browser-test.mjs — the glides, watched by a real browser.
// ===================================================================
// jsdom renders no pixels and tracks no animation state, so it can
// verify everything about the page except the one thing a player
// feels: whether a card glides to its slot or teleports. This test
// drives the built page in a real Chrome — the same artifact that
// ships — through the three ways a card moves, and samples the
// moving card's computed transform frame by frame:
//
//   click a card, click its destination   (the click-to-move path)
//   undo                                  (the plain render path)
//   hold, drag, drop                      (the pointer path)
//
// Each passes when the transform takes intermediate values between
// where the card started and where it landed; a snap shows one
// value throughout. This is the test that caught the same-tick
// re-append eating every CSS transition — twice.
//
//   (cd web && npm install)   # once: jsdom and puppeteer-core
//   node web/browser-test.mjs
//
// It uses the system's Chrome (BROWSER_PATH overrides) and skips
// with exit 0 when there is none — the jsdom suite still runs
// everywhere; the glides are watched wherever a browser exists.

import puppeteer from "puppeteer-core";
import {execFileSync} from "child_process";
import {existsSync} from "fs";
import {fileURLToPath} from "url";
import path from "path";

const root = path.dirname(fileURLToPath(import.meta.url));

// build the page first: the test checks the shipped artifact
console.log("building the page…");
execFileSync("sh", [path.join(root, "build-web.sh")], {cwd: root, stdio: "inherit"});

const CHROMES = [
  process.env.BROWSER_PATH,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium-browser",
].filter(Boolean);
const chrome = CHROMES.find(existsSync);
if (!chrome) {
  console.log("SKIPPED: no Chrome/Chromium/Edge found (set BROWSER_PATH to name one)");
  process.exit(0);
}
console.log("browser:", chrome);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const browser = await puppeteer.launch({executablePath: chrome, headless: "new"});
try {
  const page = await browser.newPage();
  await page.setViewport({width: 1000, height: 800});
  const pageErrors = [];
  page.on("pageerror", (e) => pageErrors.push(String(e)));
  await page.goto("file://" + path.join(root, "freecell.html"));
  await page.waitForFunction("!!window.freecell && !!window.freecell.game.board");

  // deal game 1, then wait out the redeal's own glides before measuring
  await page.evaluate(() => window.freecell.newGame(1));
  await sleep(350);

  // the card under test: the top of column 0, which can always go to
  // a free cell; the destination is cell 0's outline
  const key = await page.evaluate(() => {
    const toArr = (l) => { const a = []; while (l && l.$ === "Con") { a.push(l.head); l = l.tail; } return a; };
    const top = toArr(toArr(window.freecell.game.board.cascades)[0])[0];
    return top.suit.$ + "-" + top.rank.$;
  });
  const centerOf = async (sel) => page.evaluate((sel) => {
    const r = document.querySelector(sel).getBoundingClientRect();
    return {x: r.x + r.width / 2, y: r.y + r.height / 2};
  }, sel);
  const cellCenter = await centerOf("#slots .slot");
  console.log("watching:", key);

  // sample the card's computed transform every frame
  const sample = (ms = 400) => page.evaluate(async (key, ms) => {
    const el = document.querySelector(`[data-key="${key}"]`);
    const read = () => getComputedStyle(el).transform;
    const out = [];
    const t0 = performance.now();
    while (performance.now() - t0 < ms) {
      out.push(read());
      await new Promise((r) => requestAnimationFrame(r));
    }
    return {first: out[0], last: out[out.length - 1], distinct: new Set(out).size};
  }, key, ms);
  // a 160ms glide is over before the 400ms sample's midpoint, so
  // "animated" means: intermediate values appeared between a first
  // and last that differ (a snap shows one value throughout)
  const glide = (name, s) => {
    const animated = s.distinct >= 3 && s.first !== s.last;
    console.log((animated ? "ok   " : "FAIL ") + name + " glides",
                "| distinct transforms:", s.distinct);
    return animated;
  };

  let failures = 0;
  const check = (name, cond) => {
    console.log((cond ? "ok   " : "FAIL ") + name);
    if (!cond) failures++;
  };

  // 1. the player's everyday flow: click the card, click the destination
  const src = await centerOf(`[data-key="${key}"]`);
  await page.mouse.click(src.x, src.y);
  await sleep(30);
  await page.mouse.click(cellCenter.x, cellCenter.y);
  if (!glide("click-select → click-destination", await sample())) failures++;
  check("the move applied", await page.evaluate(() => window.freecell.game.moves === 1));

  // 2. undo — the plain render path
  await page.evaluate(() => window.freecell.undo());
  if (!glide("undo", await sample())) failures++;
  check("undo applied", await page.evaluate(() => window.freecell.game.moves === 0));

  // 3. drag the same card to the cell: hold, move, drop
  const src2 = await centerOf(`[data-key="${key}"]`);
  await page.mouse.move(src2.x, src2.y);
  await page.mouse.down();
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(src2.x + (cellCenter.x - src2.x) * i / 7,
                          src2.y + (cellCenter.y - src2.y) * i / 7);
    await sleep(15);
  }
  await page.mouse.up();
  if (!glide("drag → drop", await sample())) failures++;
  check("the drag applied", await page.evaluate(() => window.freecell.game.moves === 1));

  // 4. the darkening: most buried cards carry .dim, and it must
  // show in pixels, not just in the class list
  {
    const count = await page.evaluate(
      () => document.querySelectorAll("#table .card.dim").length);
    check("the buried noise is darkened (" + count + " cards)", count >= 25);
    // the working card of each column — its top of stack, the
    // bottom-most card on screen — is never darkened
    const workingLit = await page.evaluate(() => {
      const byCol = new Map();
      for (const el of document.querySelectorAll("#table .card")) {
        if (+el.dataset.y < 180) continue; // the cascades only
        const col = Math.round((+el.dataset.x - 12.5) / 125);
        const prev = byCol.get(col);
        if (!prev || +el.dataset.y > +prev.dataset.y) byCol.set(col, el);
      }
      for (const el of byCol.values()) if (el.classList.contains("dim")) return false;
      return byCol.size > 0;
    });
    check("every column's working card stays lit", workingLit);
    const key = await page.evaluate(() => {
      const el = document.querySelector("#table .card.dim");
      return el ? el.dataset.key : null;
    });
    const clip = await page.evaluate((key) => {
      const r = document.querySelector(`[data-key="${key}"] .face`).getBoundingClientRect();
      return {x: r.x, y: r.y, width: r.width, height: r.height};
    }, key);
    const withDim = await page.screenshot({clip});
    await page.evaluate((key) => document.querySelector(`[data-key="${key}"]`).classList.remove("dim"), key);
    const withoutDim = await page.screenshot({clip});
    let diff = 0;
    const n = Math.min(withDim.length, withoutDim.length);
    for (let i = 0; i < n; i++) if (withDim[i] !== withoutDim[i]) diff++;
    check("the darkening renders in pixels (" + diff + " bytes differ)", diff > n / 100);
  }

  check("no page errors", pageErrors.length === 0);
  console.log(failures === 0 ? "\nALL BROWSER TESTS PASS" : "\n" + failures + " FAILURES");
  process.exit(failures === 0 ? 0 : 1);
} finally {
  await browser.close();
}
