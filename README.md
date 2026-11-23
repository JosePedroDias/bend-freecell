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

Right now the repo holds goal 1: the abstract rules of the game in
`freecell.bend`, with the law/proof gate from `LAWS.bend` and `PROOF.bend`.

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
bend LAWS.bend       # the claims alone: prints SOME PROOFS FAIL (3 open TODOs)
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
