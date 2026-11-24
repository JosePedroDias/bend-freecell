# Optimizing Bend 2

Notes from making the freecell solver ten times faster without
changing one answer. Every strategy below was measured on this
repo, on games 1, 5, 7, 12 and the unsolvable 11982, and the
solver's line stayed byte-identical throughout — that is the
standard each change had to meet. The numbers come from one
M-series laptop (12 cores); your chip will differ, the levers
should not.

## Compile first — it is the biggest lever by far

`bend file.bend` interprets. `bend file.bend -o bin && ./bin`
compiles. For the unmodified solver this alone was worth 4.1× on
the wall clock (game 1: 64.1s interpreted, 15.7s compiled) and
13× on memory (562MB to 28MB) — the same code, the same answers.

Compiling also unlocks the parallel calls: the interpreter runs
them sequentially. A small `pow2` benchmark ran 8.1s interpreted
on one core, 1.6s compiled across seven.

Build both ways before optimizing anything. Otherwise you
credit the compiler for your own cleverness — our first round
looked like 5.5× and was 4.1× compiler, 1.5× us.

## Parallel calls, and what they ask of you

`a b = f(x) f(x)` is the parallel call: two results bound side by
side run on two cores and join at the statement after. What it
cost to learn:

- They only engage compiled (see above).
- The recursion must be the parallel call itself, textually
  inside the recursive def — a helper def holding it is a forward
  reference and will not check. Everything else moves through
  parameters.
- The checker wants a structurally smaller first argument — a
  fuel `Nat` that tails by one each split. Later arguments may
  then be computed: `List.take`/`List.drop` halves are fine once
  the fuel has shrunk.
- A binder shared by both calls must be multi-use: mark the
  parameter `+` (Data kinds only) and the shared pattern tail
  follows.
- Split contiguous, merge ordered. Halving the work into front
  and back halves, running both against the same incoming state,
  and merging by deduping the right half against the left's grown
  set keeps exactly what one sequential pass would have kept, in
  the same order. That is how the answers stayed byte-identical
  while the work spread over cores.
- Let the input choose the fuel. A flat `Bool.pick` chain at the
  caller (≤32: `0n`, ≤64: `1n`, …) turns "halve until the chunks
  are small" into a number, with no recursion for the checker to
  doubt.

One honesty: the scheduler sparked in only some runs (2.3 cores
when it did, 1.0 otherwise, same binary, same machine). Treat
parallelism as a bonus on a fast single core, not as the plan.

## Compute once, carry in the data

The beam sorts ~3,000 children a level, and its comparator asked
each entry's cost on every comparison — a full board walk,
~70,000 walks a level, for forty-nine levels. Carrying the cost
in the entry (it is known the moment the child is born) made
every comparison a field read. The reseed was rebuilding every
seen-set key it had just been given; carried in the entry, it is
a read.

Anything a comparator, an equality test or a hot loop asks for
repeatedly: compute it at construction, store it, read it.

## Compact the keys

The dedup keys spent a character on the suit and one on the rank
— ~110 characters a board. One character a card (52 codes, `'B'`
through `'u'`) took them to 68: that much less to build, that
much less to walk in the crit-bit tree. Worth about 1.5× here.

Exact keys, not hashes — a collision would only misplace a
little search, but injective packing costs nothing. The key
reads back uniquely because the trailing sections are
fixed-length: the foundations are always the last four
characters, the cells the four before them. Structure is the
cheapest checksum.

## Bound the memory, and the recursion

Two findings that began as correctness and ended as speed:

- A bounded dedup window beat an unbounded global set on both
  memory and wins. The global set starves the beam of revisits —
  the Python reference gets stuck on games 5 and 12 that the
  one-level window solves — and it grows without end.
- Dedup during construction, not after. Thread the seen-set
  through the child-building recursion, continuation style, and
  no raw list of children ever exists. That is what stopped the
  stack faults: macOS caps the machine stack near 8MB, and a
  20,000-element list is 20,000 frames if you walk it naively.

## Measure the knobs, keep the proof

- The beam's width: 256-wide beams miss game 12 entirely,
  1024-wide ones double the time for the same answers, 512 is the
  measured middle. Tuning between the passing points would fit
  the five test games and nothing else — resist it.
- Watch `user` against `real` in `/usr/bin/time`: their ratio is
  how many cores actually engaged.
- Byte-identical output is the optimization safety net. Every
  change above was proven non-semantic by diffing the solver's
  answer against the run before it — and the solver verifies its
  own line against the rules besides (`verified: True` on
  stderr).

## What we did not do, and why

- A bounded insertion window instead of sorting: keeping the best
  512 of ~3,000 by inserting into a sorted list is O(n·k), around
  750K comparisons a level, where the merge sort does ~35K. The
  sort was already the right shape.
- Reusing a level's grown seen-set as the next level's window:
  it saves a rebuild but turns the one-level window into two,
  changing which states the search sees. Not for a speed win.
- GPU calls (`f!(x)`): the guide itself says divergent work stays
  faster on the CPU, and a beam search is nothing but branches.

## The tally

The solver, before and after, same answers, byte for byte:

| game | interpreted | compiled, all of the above | speedup |
|------|-------------|---------------------------|---------|
| 1 | 64.1s / 562MB | 6.8s / 44MB | 9.4× |
| 5 | 73.5s / 549MB | 7.8s / 48MB | 9.4× |
| 7 | 60.4s / 589MB | 6.4s / 44MB | 9.4× |
| 12 | 44.7s / 508MB | 4.5s / 43MB | 9.9× |
| 11982 | 63.4s / 432MB | 7.6s / 25MB | 8.3× |
