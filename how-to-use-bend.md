# How to use Bend

Bend 2 calls itself an AI validator: a language where humans
write intents as laws, AIs write code against them, and the
compiler mechanically checks the code keeps the laws. That raises
a strategy question — should you code exclusively in Bend and
cross-compile the checked artifact to C, JS or a binary, or
validate in Bend and port the algorithms to your production
language?

The reasoning below is from this repo, where both paths were run
by accident and could be compared.

## The design closes the loop only one way

A law is a statement about a particular program. Ours —
`ms_solver_solves_game_1` — says something about `solver.bend`
and about nothing else. The moment you port, your validation is
a true statement about a program you are not shipping.

The platform is built to ship the checked thing, not just check
it: every effect in Base has a `.c` and a `.js` twin, `bend
file.bend -o out` emits a binary, C, JS or .mjs by extension,
pages bundle to the web, and `-o` can emit BendTT — a
proof-carrying artifact, recheckable by the Lean-proven kernel.

So the intended answer is: code in Bend, keep the laws beside
the code, and deploy what the laws cover.

## The porting risk, measured here

The Python reference and the Bend solver implement the same
policy — their candidate moves were diffed word for word on
identical boards. Yet they diverge in behavior: the Python one
gets stuck on games 5 and 12 because its global seen-set starves
the beam, while the one-level window solves both.

Same algorithm, same policy, different outcomes. That is what a
port does at scale: it drifts, and the laws do not follow it. A
Bend validation of a ported system would have been true and
useless — true about the Bend program, useless about the one in
production.

## When porting is still right

- The target stack is fixed — an existing system, a team, a
  regulation. Bend cannot reach into a Java monolith.
- Performance favors it — the Python twin still wins game 7
  (2.3s against 6.4s), though compiled Bend is competitive and
  better on the hard games.
- Runtime maturity matters — this repo hit a flaky parallel
  scheduler and an interpreter that runs parallel calls
  sequentially; for production, that counts.

When a port is forced, the discipline is not copying the
algorithms and edge cases — the edge cases do not transfer. The
discipline is differential testing against the Bend oracle:
same inputs into both, diff the outputs, in CI, forever. This
repo did it once, by hand, with the candidate diff; a real port
does it on every commit. The port is always one refactor away
from quietly invalidating the validation.

## Who do you trust

Shipping compiled Bend trusts the checker — auditable through
`--verdict` and its Lean kernel — and the C codegen: mechanical,
reproducible, one implementation. Porting trusts the porter:
human or AI, and drift-prone by nature. A mechanical base is the
safer bet. One nuance: the verdict proves the checking, not the
codegen — the compiler's backend is trusted, not proven.

## What this repo does

Bend is the source of truth wherever its effects can reach. The
server went Bend-only because sockets, files and processes are
native effects, so the whole thing stays under the laws —
`server_governs_its_games` covers exactly what ships. The Python
solver is kept as a curiosity, validated against Bend rather
than the reverse. Where a port is forced: differential testing,
continuously, and the laws live with the artifact that must keep
them.

## Proving costs more than running

One wrinkle shapes the whole workflow: normalizing the solver
law takes the checker hours where the runtime takes seconds.
Keep the per-commit laws cheap to check — like the server's —
and spend the deep proofs at release time. The AI-validator
loop only works if it can gate every change an AI makes, and a
gate that takes hours gates nothing.
