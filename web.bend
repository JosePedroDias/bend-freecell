import Base
import ./freecell.bend as F
import ./solver.bend as S

# ===================================================================
# The web entry: one module for everything a browser page calls.
# ===================================================================
# The page imports this file and calls the defs — the rules and
# the deals straight from freecell.bend, the search from
# solver.bend — so the shipped page runs the checked code, not a
# port of it. The game is the functions; the page is the face.
#
# The search is driven by hand: Solver.first hands the opening
# state to the page, and Beam.step advances it one level at a
# time, so a solve can yield between levels instead of freezing
# the interface for the whole search. Every other call is one
# def.
#
# main is a self-check of the calling convention the page uses:
# the rules consulted, a refusal taken, the autoplay replayed,
# the search stepped by hand. It prints "web api ok" and quits,
# the same pattern as the server's House.self_check.

# --- The self-check's helpers ------------------------------------

def Web.try_all(ms: +List<F.Move>, got: Maybe<&2, F.Board>) -> Maybe<&2, F.Board>:
  # the moves one by one; the first illegal one ends the line
  match ms got:
    case Nil{} _:
      got
    case _ None{}:
      None{}
    case Con{m, rest} Some{b}:
      Web.try_all(rest, F.Board.apply(b, m))

def Web.expect(ok: Bool, msg: String) -> IO(Unit):
  # say nothing when ok holds; die with the reason when it does not
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "web api: " ++ msg)

def Web.autoplay_kept(got: Maybe<&2, F.Board>, +b: F.Board) -> Bool:
  # the replay ended, and no card was lost on the way
  match got:
    case Some{b2}:
      U32.is_eq(F.Board.card_count(b), F.Board.card_count(b2))
    case None{}:
      False{}

def Web.autoplay_ok(ms: +List<F.Move>, +b: F.Board) -> Bool:
  # the safe home moves are all legal, and no card is lost on them
  Web.autoplay_kept(Web.try_all(ms, Some{b}), b)

def Web.autos_of(pair: F.Board & +List<F.Move>) -> +List<F.Move>:
  # just the moves of an autoplayed pair
  (_, autos) = pair
  autos

def Web.beam_left(m: S.Search, k: Nat) -> IO(Unit):
  # a stepped search is still a beam, with k levels left on it
  match m:
    case S.Beam{_, left, _}:
      Web.expect(Nat.is_eq(left, k), "the beam's level budget is wrong")
    case _:
      IO.die(Unit, 1, "web api: a live search should still be a beam")

# --- The self-check ----------------------------------------------

def main() -> IO(Unit):
  do IO<Unit>:
    +b : F.Board = F.Board.deal_ms(1)
    Web.expect(U32.is_eq(F.Board.card_count(b), 52), "game 1 should hold 52 cards")
    Web.expect(Bool.not(F.Board.is_won(b)), "a fresh deal is not won")
    Web.expect(Bool.not(F.Board.can_move(b, F.CascadeToFoundation{0})), "the jack of diamonds may not start a foundation")
    pair : F.Board & +List<F.Move> = S.Solver.autoplay(64n, b)
    Web.expect(Web.autoplay_ok(Web.autos_of(pair), b), "the autoplay moves are all legal")
    +opened : S.Search = S.Solver.first(S.Solver.autoplay(64n, b), 3n)
    +stepped : S.Search = S.Beam.step(S.Beam.step(opened))
    Web.beam_left(stepped, 1n)
    IO.print("web api ok\n")
