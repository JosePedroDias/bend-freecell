# Freecell cards game in bend

## Practical Notes

I have installed bend into ~/.bend

you can make it executable in the fish shell by running

```
fish_add_path $HOME/.bend/bin
```

## What this is

Freecell in Bend 2, end to end: the abstract rules and the
classic Microsoft deals in `freecell.bend`, the law/proof gate
in `LAWS.bend` and `PROOF.bend`, a terminal game in
`terminal-game.bend`, a beam-search solver in `solver.bend`, and
an authoritative HTTP server in `server.bend` — one language,
one rule book, every move in every face of the game judged by
the same defs. The five goals the repo set out with are all
built.

## The documents

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
- [AGENTS.md](AGENTS.md) — the working rules this repo was built
  under

## Usage

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
  1-8  a cascade column    a-d  a free cell    h  the foundation
  e.g. '1 2'  the top of column 1 onto column 2
```

Plus `u` (undo), `h` (help) and `q` (quit); the end of input quits
too. A scripted session works over a pipe:

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
bend solver.bend -o solver && ./solver 1     # ~10s and ~40MB
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

### Run the rules demo

```bash
bend freecell.bend
```

`main` exercises every rule on a small hand-made board (legal and illegal
cascade stacking, the Ace starting a foundation, occupied vs free cells),
applies a legal move to show the transition, then deals a full natural
deck. Expected output, abridged:

```
a small board:
cells: [AC, --, --, --]  founds: [0, 0, 0, 0]
cascades:
  [KH]
  [QS]
  ...
cascade 1 to cascade 0: legal (the board still holds 3 cards)
cascade 1 to foundation: illegal
cell 0 to foundation: legal (the board still holds 3 cards)
...
a full deal of a natural deck:
cascades:
  [TC, 2C, 7D, QH, 4H, 9S, AS]
  ...
```

### Check the laws

```bash
bend PROOF.bend      # the gate: prints ALL PROOFS CHECK
bend LAWS.bend       # the claims alone: prints SOME PROOFS FAIL (the open claims, by design)
```

`LAWS.bend` states the laws as open claims and `PROOF.bend` fills them in,
so only `PROOF.bend` goes green. Run it before every commit (see AGENTS.md).
`bend PROOF.bend --verdict` re-checks with the BendTT kernel, if Lean
v4.34.0 is installed. One law runs the whole solver on game 1, so the
gate takes about a minute.

### Build a native binary

```bash
bend freecell.bend -o freecell && ./freecell
```

### Reading the rules

The rule book lives in `freecell.bend`:

- `Card.can_stack_on` — the cascade rule (one rank lower, opposite color)
- `Founds.next_ok` — the foundation rule (rank n+1 next; the Ace starts one)
- `Board.move_ok` — all five moves checked against the rules
- `Board.force` — perform a legal move unchecked (for the future solver)
- `Board.apply` — the authoritative transition: `Some(next board)` iff legal
- `Board.is_won` — every foundation holds all 13 cards

### Reference

```bash
bend guide          # the language guide
bend base           # the Base library (bend base List for one module)
bend --help         # all commands
```
