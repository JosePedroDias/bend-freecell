# The Python reference solver

The prototype the Bend solver (`../solver.bend`) was checked
against while the Bend was being written. That was its real job:
confirming we were programming Bend correctly. A new policy in a
new language is easy to get subtly wrong, and diffing the two,
move for move on the same boards, found the mistakes. It encodes
the same policy as the classic reference solvers: safe autoplay
after every move, supermoves capped by the free cells, and a beam
search whose states are deduplicated through a seen-set keyed by
the board.

    python3 beam.py 1        # solve game 1
    python3 beam.py 5 v      # solve game 5, with a level trace
    python3 beam.py 11982    # the famously unsolvable game

It solved the Microsoft deals before the Bend solver existed —
game 1 in 79 moves at beam width 1024 — and the Bend solver was
then written to match it, policy for policy. The diff earned its
keep more than once: it caught a misindexed supermove scan in the
Bend that offered an illegal move and never found some legal
ones. Once the candidates agreed, board by board, the two were
benchmarked against each other. The Python is still quicker on
the easy games (game 7 in 2.3s against the compiled Bend's 6.4s);
the Bend wins the ones the Python's global seen-set starves on —
games 5 and 12 — where the one-level window still finds the win.
Game 11982 stays unsolved in both.

## The autoplay bug, found late (2026-11-25)

The numbers above were measured on a subtly wrong autoplay. The
legality checks (`can_found`, `safe_found`, `homes`) read the
solve-scope `founds` through a closure while `autoplay` mutated
its own local copy — so every home move after the first in one
burst was checked against the burst's *starting* foundations. A
two that follows its ace in the same burst was suppressed; the
Bend solver, which threads the real board, played it. The search
was never the policy it claimed to be.

The fix passes `founds` explicitly. Measured before → after, beam
width 512: game 1 went from 185 moves at level 124 to **68 moves
at level 49** (and 3.5× faster); at width 1024 the old 79 moves
became 65. Game 7 took a longer line under the same cost — the
estimate charges for the home moves, so honest autoplay reshuffles
the ranking (103 moves at level 54 became 297 at level 162). Games
5 and 12 still starve: that is the seen-set window, the porting
drift `../HOW-TO-USE-BEND.md` documents, and it is untouched here.

Three divergences from the Bend solver remain, all deliberate or
documented: the global forever-window, the bottom-up unsorted count
(Bend counts the top run), and recorded lines that omit the home
moves the search played — so its lines cannot replay on a game
that does not auto-play. The full parity story, including this
bug's diagnosis, is in the sibling Dafny port's `SOLVER.md`.
