# Freecell cards game in bend

## Practical Notes

I have installed bend into ~/.bend

you can make it executable in the fish shell by running

```
fish_add_path $HOME/.bend/bin
```

## Goals

1. I want to encode the abstract rules of the freecell card game in bend.
2. I want to write the laws that enforce those the game rules hold
3. I want to create a terminal freecell game with basic ascii representation
4. I want to create a freecell solver
5. I want to create an HTTP authoritative server that drives an abstract game of freecell (or multiple ones?)

## Usage

Right now the repo holds goals 1-3: the abstract rules in
`freecell.bend` (including the classic Microsoft deals), the
law/proof gate from `LAWS.bend` and `PROOF.bend`, and the terminal
game in `terminal-game.bend`.

### Play the terminal game

```bash
bend terminal-game.bend            # game 1
bend terminal-game.bend 11982      # any Microsoft game number
```

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
v4.34.0 is installed.

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
