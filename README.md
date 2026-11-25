# Freecell card game in Bend

## TL;DR

Freecell in Bend 2, end to end:
- the abstract rules and the classic Microsoft deals in `freecell.bend`,
- the law/proof gate in `LAWS.bend` and `PROOF.bend`,
- a terminal game in `terminal-game.bend`,
- a beam-search solver in `solver.bend`,
- an authoritative HTTP server in `server.bend`,
- and a browser game in `web/`, bundled by `./web/build-web.sh`.


## The documents
- [AGENTS.md](AGENTS.md) — the working rules this repo was built
  under (as suggested by bend's docs)
- [OPTIMIZING.md](OPTIMIZING.md) — what the solver's speed work
  taught about optimizing Bend 2: the measured levers, and the
  traps
- [HOW-TO-USE-BEND.md](HOW-TO-USE-BEND.md) — the strategy
  question: code in Bend and ship the checked artifact, or
  validate in Bend and port
- [python-reference/README.md](python-reference/README.md) — the
  Python prototype that confirmed the Bend solver was being
  written correctly: the deals, then the candidate moves, were
  diffed board by board, and the diff caught real bugs. Kept for
  curiosity, with the benchmark that compared the two


## Usage

### Play in the browser

```bash
./web/build-web.sh       # writes web/freecell.html: one self-contained file
open web/freecell.html   # or just double-click it
```

The page is the compiled game. Bend bundles `web/web.html` — its SVG
interface and the bend code it imports, through `web/web.bend` —
into one JavaScript chunk, and `build-web.sh` splices that chunk
back into the page. The result opens with a double-click: no
server, no network, one file. Every game decision — the deal, the
legality of a move, the board it produces, the win, the safe home
moves, the search — is a call into the bundled checked code; the
page only draws the answers and reads the clicks.

Drag a card, or click a card and then its destination;
double-click sends a card home when the rules allow it. A column's
run — its working card and the cards stacked on it, up to the one
you grab — crosses to another column in one gesture, expanded by
the module into single moves that the page plays a beat apart,
every one checked by the rules; the whole crossing is one undo,
and the cells and empty columns set how much one gesture can
carry. Buried
cards that are not aces, not wanted by their foundations, and not
part of a rising run — each card a place the one beneath it can
rest on — are darkened: the noise to clear away. The module names
them, the page dims them, and a card in hand is always fully lit.
`Undo`
and `Redo` walk the history, `Safe` plays every safe home move at
once, and `Solve` beam-searches for a winning line — one level
per beat, with a progress bar, so the page never freezes — then
offers to play the line move by move. The clock starts with the
deal; `Pause` (or `p`) holds it and hides the cards, so a break
is not on the record. The page opens on a random
solvable game, and so does `New` (the classic range, 11982
re-rolled); a number and `Deal` deal exactly that game. The
address names the game in play — `web/freecell.html#4242` is
game 4242, ready to send to a friend — and every deal writes it
there.

### Test the web build

```bash
(cd web && npm install)  # once: jsdom, for the page's test
node web/web-test.mjs    # builds the page, then drives it
```

The page's answers come from the bundled bend code, but its hands —
the SVG, the pointer, the clock — answer to the DOM. The test loads
the built artifact into jsdom and plays it: renders all 52 cards,
has the rules refuse an illegal move and take a legal one, walks
undo and redo, sends a safe ace home, wins a crafted endgame to see
the banner, opens a search within a small budget, checks every
column's paint order (including a card that lands exactly where it
already was), checks the darkening of the buried noise, and checks
the deal box and the address name the game. It is the cheap gate
for `web/web.html`.

jsdom renders no pixels, so it cannot see whether a card glides to
its slot or teleports. The glides are watched in a real browser:

```bash
node web/browser-test.mjs   # needs a Chrome, Chromium or Edge
```

It drives the built page through the three ways a card moves —
click-then-click, undo, drag-and-drop — and samples the moving
card's computed transform frame by frame; a check passes only when
the card took intermediate positions between its slots. It skips,
with exit 0, on a machine with no browser to drive.

The search the page drives — `Solver.first` stepped by `Beam.step`
— is a port of the checked search in
[HOW-TO-USE-BEND.md](HOW-TO-USE-BEND.md)'s sense, so it carries the
differential test that document asks of a port: same board into
both paths, same winning line out.

```bash
node web/solver-test.mjs   # ~40s: the stepped line == the one-shot line
```

That one takes the deep path — two full searches — so it gates
`solver.bend` changes, not every commit.

### Play the terminal game

```bash
bend terminal-game.bend            # a random solvable game
bend terminal-game.bend 11982      # any Microsoft game number
```

Without an argument, the game draws a random number from the
classic range 1-32000 and prints which it elected — every deal in
that range is solvable but #11982 (the published fact), which is
re-rolled; a number on the command line deals exactly that game.

The deals are the classic Microsoft ones, so game numbers match the
published layouts (game 1 opens JD 2D 9H JC 5D 7H 7C 5H). Moves are
two words, `<from> <to>`:

```
  1-8  a cascade column
  a-d  a free cell
  h    the foundation
  
  e.g. '1 2'  the top of column 1 onto column 2
```

Plus `u` (undo),
`h` (help) and
`q` (quit)

A scripted session works over a pipe:

```bash
printf "1 a\n1 2\nu\nq\n" | bend terminal-game.bend
```

### Solve a game

```bash
bend solver.bend 1        # game 1: a winning line, one move a line
bend solver.bend 11982    # the famous unsolvable one: says so
```

The solver is a beam search after the reference solvers: after every
candidate move the safe home moves play themselves, so the line it
prints only needs the interesting moves; run moves (supermoves) are
candidates too, expanded into the single moves the rules take. Each
level keeps the best 512 boards by cost — cards not home, plus
unsorted cards, plus used cells, plus the home moves already made,
each read once where a child is born — and a state is only visited
once per level window. 256-wide beams miss game 12 and 1024-wide
ones double the time for the same answers, so 512 is the measured
middle. The level's halves expand against the same
window in parallel and merge in order, so the answer is the one the
sequential scan would have given; the answer is verified against
the rules before it is printed (`verified: True` on stderr).

Interpreted, a game number takes about a minute; the parallel
calls engage in a compiled binary, which is also much faster on
one core:

```bash
bend solver.bend -o solver && ./solver 1     # ~7s and ~44MB
```

Pipe the line straight into the terminal game and watch it win:

```bash
bend solver.bend 1 2>/dev/null | bend terminal-game.bend 1
```

`python-reference/` holds the Python prototype the Bend solver
was checked against while it was written — the two were diffed
board by board, and the diff caught real Bend bugs. It stays for
curiosity; [its README](python-reference/README.md) tells the
story.

### Play over HTTP

```bash
bend server.bend            # an authoritative server on :8080
bend server.bend 9090        # another port
```

The state lives in the server and nowhere else: every move is
checked against the rules before it is believed, and several
games can be open at once, each named by its number. Requests
speak HTTP/1.0 and each connection carries one request:

```bash
curl localhost:8080/1               # deal game 1, see it as JSON
curl localhost:8080/1 -d "1 a"      # a move, the terminal game's words
curl localhost:8080/1 -d "u"        # take it back
curl localhost:8080/1 -d "h"        # the commands, as JSON
curl localhost:8080/games            # the open games
```

Answers are JSON: the whole board — `cells`, `foundations` (suit
by suit), `cascades` (each column bottom card first) and `won` —
or `{"error": ...}` with a 4xx when the request or the move
cannot be honored. The commands are the terminal game's own
two-word moves, so a whole winning line can be piped in move by
move:

```bash
bend solver.bend 1 2>/dev/null |
  while read a b; do curl -s localhost:8080/1 -d "$a $b" > /dev/null; done
curl -s localhost:8080/1            # "won": true
```

One connection is served at a time — freecell is a turn-based
game — and the server says so on stderr when it starts, after
running its own self check against the rules.


### Check the laws

```bash
bend PROOF.bend      # the gate: prints ALL PROOFS CHECK
bend LAWS.bend       # the claims alone: prints SOME PROOFS FAIL (the open claims, by design)
```

`LAWS.bend` states the laws as open claims and `PROOF.bend` fills them in, so only `PROOF.bend` goes green.
Run it before every commit (see AGENTS.md).
`bend PROOF.bend --verdict` re-checks with the BendTT kernel, if Lean v4.34.0 is installed.

The solver's own claim — a game number in, a rule-verified winning
line out — is carried by the program itself: every solve replays
its line against the rules and prints `verified: True`. It lived
as a law once; the checker could not afford the search, and a law
that cannot be checked protects nothing.


### Reading the rules

The rule book lives in `freecell.bend`:

- `Card.can_stack_on` — the cascade rule (one rank lower, opposite color)
- `Founds.next_ok` — the foundation rule (rank n+1 next; the Ace starts one)
- `Board.move_ok` — all five moves checked against the rules
- `Board.force` — perform a legal move unchecked (for the future solver)
- `Board.apply` — the authoritative transition: `Some(next board)` iff legal
- `Board.is_won` — every foundation holds all 13 cards
