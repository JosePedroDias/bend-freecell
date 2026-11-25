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

def Web.is_ace(c: F.Card) -> Bool:
  # any suit's ace: always free to go home, never noise
  match c:
    case F.Card{_, rank}:
      F.Rank.is_eq(rank, F.Ace{})

def Web.is_noise(+c: F.Card, +below: F.Card, +founds: +List<U32>) -> Bool:
  # a buried card is noise when it is no ace, its foundation does
  # not want it next, and the card beneath it cannot rest on it: a
  # lit column reads bottom-to-top as building order, each card
  # ready to hop onto the one above it — 6S 7H 8C climbs, 8C 7H 6S
  # does not
  Bool.not(Web.is_ace(c)) && Bool.not(F.Founds.takes(founds, c)) && Bool.not(F.Card.can_stack_on(below, c))

def Web.dim_rest(p: +List<F.Card>, below: F.Card, +founds: +List<U32>, +acc: +List<F.Card>) -> +List<F.Card>:
  # the cards above a column's working one, each judged against the
  # card beneath it. Piles are top-first — the working card is the
  # head — so the card beneath, on screen, is the previous card, the
  # one dealt onto it later
  match p:
    case Nil{}:
      acc
    case +card <> rest:
      Web.dim_rest(rest, card, founds,
        Bool.pick(+List<F.Card>, Web.is_noise(card, below, founds), card <> acc, acc))

def Web.dim_pile(p: +List<F.Card>, +founds: +List<U32>, +acc: +List<F.Card>) -> +List<F.Card>:
  # one column: its working card — the top of the stack, the
  # bottom-most on screen, the one a player can always pick up — is
  # never noise; every card above it is judged against the card
  # beneath each
  match p:
    case Nil{}:
      acc
    case top <> rest:
      Web.dim_rest(rest, top, founds, acc)

def Web.dim_piles(piles: +List<+List<F.Card>>, +founds: +List<U32>, +acc: +List<F.Card>) -> +List<F.Card>:
  # every column's noise
  match piles:
    case Nil{}:
      acc
    case +p <> ps:
      Web.dim_piles(ps, founds, Web.dim_pile(p, founds, acc))

def Web.dim_witness() -> F.Board:
  # a board for the dim law: a column that climbs, a column that
  # falls, a buried ace, a buried card its foundation wants next,
  # a card parked in a cell and one already home. The law states
  # the exact noise; this is the board it is stated on
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Spades{}, F.Six{}} <> (F.Card{F.Hearts{}, F.Seven{}} <> (F.Card{F.Clubs{}, F.Eight{}} <> empty)),
     F.Card{F.Diamonds{}, F.Jack{}} <> (F.Card{F.Spades{}, F.Ten{}} <> (F.Card{F.Hearts{}, F.Nine{}} <> empty)),
     F.Card{F.Spades{}, F.King{}} <> (F.Card{F.Hearts{}, F.Ace{}} <> (F.Card{F.Clubs{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Nine{}} <> (F.Card{F.Spades{}, F.Two{}} <> empty),
     empty, empty, empty, empty],
    [Some{F.Card{F.Diamonds{}, F.Eight{}}}, None{}, None{}, None{}],
    [1, 0, 0, 0]}

def Web.dim(b: F.Board) -> +List<F.Card>:
  # the cards the page darkens: buried cards that are no aces, are
  # not wanted home, and do not continue a rising run — the card
  # beneath them cannot rest on them. A column's working card — the
  # top of its stack, the bottom-most on screen, the one a player
  # can always pick up — every ace, every foundation-ready card and
  # every card of a run climbing from the bottom stay lit; cells
  # and foundations are never darkened at all
  match b:
    case F.Board{cascades, _, founds}:
      Web.dim_piles(cascades, founds, {Nil{} : +List<F.Card>})

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
    # the dim vocabulary on the witness board: the climbing column
    # stays fully lit, the falling one darkens above its working
    # card, the buried ace and the wanted two stay lit — so exactly
    # the five, the nine and the ten are named, in the walk's order
    Web.expect(F.Pile.is_eq(Web.dim(Web.dim_witness()),
      [F.Card{F.Clubs{}, F.Five{}}, F.Card{F.Hearts{}, F.Nine{}}, F.Card{F.Spades{}, F.Ten{}}]),
      "the dim rule should name the five, the nine and the ten")
    IO.print("web api ok\n")
