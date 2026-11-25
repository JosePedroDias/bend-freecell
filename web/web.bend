import Base
import ../freecell.bend as F
import ../solver.bend as S

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

# --- The page's vocabulary ---------------------------------------
# Everything a driver may call, under names that do not move when
# the files do. The JS sees the "Web.*" keys alone — never the
# path-prefixed names of the modules beneath — so the page and its
# tests survive a re-arranged tree.

def Web.deal(game: U32) -> F.Board:
  # the classic Microsoft deal by game number
  F.Board.deal_ms(game)

def Web.move_ok(b: F.Board, m: F.Move) -> Bool:
  # is m a legal move on b?
  F.Board.can_move(b, m)

def Web.move(b: F.Board, m: F.Move) -> Maybe<&2, F.Board>:
  # the next board iff m is legal — the authoritative transition
  F.Board.apply(b, m)

def Web.won(b: F.Board) -> Bool:
  # every foundation complete
  F.Board.is_won(b)

def Web.safe(+b: F.Board) -> F.Board & +List<F.Move>:
  # every safe home move, and the board after them
  S.Solver.autoplay(64n, b)

def Web.open(b: F.Board, levels: Nat) -> S.Search:
  # the search's opening state, for a driver that steps it one
  # level at a time
  S.Solver.first(S.Solver.autoplay(64n, b), levels)

def Web.step(m: S.Search) -> S.Search:
  # one beam level of the search
  S.Beam.step(m)

def Web.deep(levels: Nat, b: F.Board) -> S.Search:
  # the whole search in one call: the CLI solver's own path,
  # exposed for the differential test that checks the stepped
  # path against it
  S.Solver.solve(levels, b)

def Web.move_word(m: F.Move) -> String:
  # a move in the words the terminal game takes, for reading a
  # winning line
  S.Solve.word(m)

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
