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
