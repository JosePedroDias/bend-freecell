# The Python reference solver

This is the prototype the Bend solver (`../solver.bend`) was
validated against, kept for intellectual curiosity. It encodes the
same policy as the classic reference solvers: safe autoplay after
every move, supermoves capped by the free cells, and a beam search
whose states are deduplicated through a seen-set keyed by the board.

    python3 beam.py 1        # solve game 1
    python3 beam.py 5 v      # solve game 5, with a level trace
    python3 beam.py 11982    # the famously unsolvable game

It solved the Microsoft deals before the Bend solver existed — game 1
in 79 moves at beam width 1024 — and the Bend solver was then written
to match it, policy for policy. During development the two were
diffed move for move: for the same boards they generate the same
candidate moves, and they agree on which games are solvable. Game
11982 stays unsolved in both.
