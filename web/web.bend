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

# --- Supermoves ---------------------------------------------------
# A supermove carries a run — a column's working card and the cards
# stacked on it, the same rising structure the dim rule lights — to
# another column in one gesture. The rules take only single moves,
# so a supermove is expanded into them:
#   - when the free cells can hold all but the run's top card, the
#     solver's own expansion does it: park, land, restack (the
#     cells give the run back in reverse);
#   - when they cannot, a spare empty column stages the run's
#     lower half while the rest crosses, halving the work until
#     every half fits.
# The whole capacity a gesture may carry is (free cells + 1),
# doubled once per other empty column. The expansion is a
# trampoline after Beam.tramp: a queue of jobs, one unit of fuel
# each, and every move it emits is checked again by Board.apply as
# the page plays it.

type Job is Data:
  # one piece of a supermove: carry k cards from column i to j
  Job{k: U32, i: U32, j: U32}

type Step is Data:
  # the trampoline's world after one job: the board as it stands,
  # the queue still to walk, the moves already spent
  Step{board: F.Board, jobs: +List<Job>, moves: +List<F.Move>}

type Haul is Data:
  # a supermove's answer: the board it reaches, and the moves it
  # took — every one legal where it was played
  Haul{board: F.Board, moves: +List<F.Move>}

def Web.piles_of(b: F.Board) -> +List<+List<F.Card>>:
  match b:
    case F.Board{cascades, _, _}:
      cascades

def Web.cells_of(b: F.Board) -> +List<+Maybe<F.Card>>:
  match b:
    case F.Board{_, cells, _}:
      cells

def Web.free_cells(b: F.Board) -> U32:
  # how many cells stand free
  S.Solver.free_count(Web.cells_of(b))

def Web.grab(b: F.Board, col: U32) -> U32:
  # how many cards a column can hand over at once: its rising run,
  # counted from the working card. A card at depth d is grabbable
  # iff d is below this
  F.Pile.run_len(Maybe.default(&2, +List<F.Card>, F.Piles.get(Web.piles_of(b), col), {Nil{} : +List<F.Card>}))

def Web.empties(+piles: +List<+List<F.Card>>, +i: U32, +j: U32, +c: U32) -> U32:
  # how many columns stand empty, besides the source and the target
  match piles:
    case Nil{}:
      0
    case +p <> +ps:
      +x : U32 = Web.empties(ps, i, j, U32.add(c, 1))
      Bool.pick(U32, S.Solver.blank(p) && U32.is_ne(c, i) && U32.is_ne(c, j), (1 + x : U32), x)

def Web.capacity(+b: F.Board, +i: U32, +j: U32) -> U32:
  # how many cards one gesture can carry from i to j: the free
  # cells plus one, doubled once per other empty column
  U32.mul(U32.add(Web.free_cells(b), 1),
    U32.shln(1, U32.to_nat(Web.empties(Web.piles_of(b), i, j, 0))))

def Web.target_pile(b: F.Board, +j: U32) -> +List<F.Card>:
  Maybe.default(&2, +List<F.Card>, F.Piles.get(Web.piles_of(b), j), {Nil{} : +List<F.Card>})

def Web.lands_q(+q: +List<F.Card>, +top: F.Card) -> Bool:
  # the target takes the run's top card: empty, or loaded and
  # accepting it
  match q:
    case Nil{}:
      True{}
    case _ <> _:
      S.Solver.builds_on(q, top)

def Web.lands(b: F.Board, +j: U32, +top: F.Card) -> Bool:
  Web.lands_q(Web.target_pile(b, j), top)

def Web.run_top(+pile: +List<F.Card>, +upto: U32) -> Maybe<&2, F.Card>:
  # the grabbed card: the top of the run that crosses
  List.get(&2, F.Card, pile, U32.to_nat(upto))

def Web.takes_top(b: F.Board, +j: U32, top: Maybe<&2, F.Card>) -> Bool:
  # the target takes the run's top card — or the run is not real
  match top:
    case None{}:
      False{}
    case Some{+t}:
      Web.lands(b, j, t)

def Web.spare(+piles: +List<+List<F.Card>>, +i: U32, +j: U32, +c: U32) -> Maybe<&2, U32>:
  # the first empty column besides the source and the target
  match piles:
    case Nil{}:
      None{}
    case +p <> +ps:
      Bool.pick(Maybe<&2, U32>, S.Solver.blank(p) && U32.is_ne(c, i) && U32.is_ne(c, j),
        Some{c}, Web.spare(ps, i, j, U32.add(c, 1)))

def Web.job_one_go(got: Maybe<&2, F.Board>, +m: F.Move, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  match got:
    case Some{b2}:
      Some{Step{b2, rest, List.append(&2, F.Move, acc, m <> {Nil{} : +List<F.Move>})}}
    case None{}:
      None{}

def Web.job_one(+b: F.Board, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # one card across
  Web.job_one_go(F.Board.apply(b, F.CascadeToCascade{i, j}), F.CascadeToCascade{i, j}, rest, acc)

def Web.job_cells_go(got: Maybe<&2, F.Board>, +ms: +List<F.Move>, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  match got:
    case Some{b2}:
      Some{Step{b2, rest, List.append(&2, F.Move, acc, ms)}}
    case None{}:
      None{}

def Web.job_cells(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # the cells alone can hold all but the top card: the solver's own
  # expansion, replayed move by move on the board
  +ms : +List<F.Move> = S.Solver.expand_super(i, j, c, Web.cells_of(b))
  Web.job_cells_go(Web.try_all(ms, Some{b}), ms, rest, acc)

def Web.job_split_go(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, spare: Maybe<&2, U32>) -> Maybe<&2, Step>:
  match spare:
    case None{}:
      None{}    # cannot happen: the entry's capacity check promised one
    case Some{+e}:
      # the staged half is as large as the remaining emptiness can
      # still carry: (free cells + 1), doubled by the empties the
      # staging column itself leaves
      cap : U32 = U32.mul(U32.add(Web.free_cells(b), 1),
        U32.shln(1, U32.to_nat(U32.sub(Web.empties(Web.piles_of(b), i, j, 0), 1))))
      +m : U32 = U32.min(U32.sub(c, 1), cap)
      +s : U32 = U32.sub(c, m)
      # the lower half stages on e, the rest crosses, the stage
      # follows: three jobs, in that order, ahead of everything
      Some{Step{b, Job{s, i, e} <> (Job{m, i, j} <> (Job{s, e, j} <> rest)), acc}}

def Web.job_split(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # too many cards for the cells alone: a spare empty column
  # stages the lower half
  Web.job_split_go(b, c, i, j, rest, acc, Web.spare(Web.piles_of(b), i, j, 0))

def Web.job_big(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, fits: Bool) -> Maybe<&2, Step>:
  match fits:
    case True{}:
      Web.job_cells(b, c, i, j, rest, acc)
    case False{}:
      Web.job_split(b, c, i, j, rest, acc)

def Web.job_pick(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, one: Bool) -> Maybe<&2, Step>:
  match one:
    case True{}:
      Web.job_one(b, i, j, rest, acc)
    case False{}:
      Web.job_big(b, c, i, j, rest, acc, U32.is_le(U32.sub(c, 1), Web.free_cells(b)))

def Web.job_effect(+b: F.Board, +job: Job, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # one job's whole effect — the board after its moves, the queue
  # with its children, the moves it spent — with no recursion in
  # it: the trampoline in Web.work does the walking
  match job:
    case Job{+c, +i, +j}:
      Web.job_pick(b, c, i, j, rest, acc, U32.is_eq(c, 1))

def Web.work_done(got: Maybe<&2, Step>,
                  k: F.Board -> +List<Job> -> +List<F.Move> -> Maybe<&2, Haul>) -> Maybe<&2, Haul>:
  match got:
    case Some{Step{+b2, +jobs2, +acc2}}:
      k(b2)(jobs2)(acc2)
    case None{}:
      None{}

def Web.work_step(+b: F.Board, +job: Job, +rest: +List<Job>, +acc: +List<F.Move>,
                  k: F.Board -> +List<Job> -> +List<F.Move> -> Maybe<&2, Haul>) -> Maybe<&2, Haul>:
  # one job, then the caller's continuation: the trampoline step
  Web.work_done(Web.job_effect(b, job, rest, acc), k)

def Web.work(fuel: Nat, +b: F.Board, jobs: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Haul>:
  # the supermove trampoline: one job per unit of fuel, until the
  # queue runs dry. A run of thirteen spends at most ~25 jobs, so
  # 64 fuel covers any board. The closure below is the only
  # recursion, and the fuel rides inside it
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match jobs:
        case Nil{}:
          Some{Haul{b, acc}}
        case +job <> +rest:
          Web.work_step(b, job, rest, acc,
            (b2) => (jobs2) => (acc2) => Web.work(p, b2, jobs2, acc2))

def Web.is_some_super(got: Maybe<&2, Haul>) -> Bool:
  # did the run cross?
  match got:
    case Some{_}:
      True{}
    case None{}:
      False{}

def Web.super_check(got: Maybe<&2, Haul>, +want: F.Board, +n: Nat) -> Bool:
  # the run crossed, reached exactly the wanted board, and spent
  # exactly n moves
  match got:
    case None{}:
      False{}
    case Some{Haul{b2, ms}}:
      F.Board.is_eq(b2, want) && Nat.is_eq(List.length(&2, F.Move, ms), n)

def Web.super_ok(+b: F.Board, +col: U32, +upto: U32, +target: U32) -> Bool:
  # every promise a supermove asks, in one answer: the grabbed
  # cards climb from the working card, the target is another column
  # and takes the run's top card, and the cells and empty columns
  # can carry it all
  +pile : +List<F.Card> = Maybe.default(&2, +List<F.Card>, F.Piles.get(Web.piles_of(b), col), {Nil{} : +List<F.Card>})
  run_ok : Bool = U32.is_lt(upto, F.Pile.run_len(pile))
  top : Maybe<&2, F.Card> = Web.run_top(pile, upto)
  U32.is_ne(target, col) && run_ok && Web.takes_top(b, target, top) && U32.is_le(U32.add(upto, 1), Web.capacity(b, col, target))

def Web.super_go(+b: F.Board, +col: U32, +upto: U32, +target: U32, ok: Bool) -> Maybe<&2, Haul>:
  match ok:
    case True{}:
      Web.work(64n, b, Job{U32.add(upto, 1), col, target} <> {Nil{} : +List<Job>}, {Nil{} : +List<F.Move>})
    case False{}:
      None{}

def Web.supermove(+b: F.Board, +col: U32, +upto: U32, +target: U32) -> Maybe<&2, Haul>:
  # the atomic moves of carrying a run — a column's working card
  # and the cards stacked on it, up to the grabbed one — onto
  # another column: Some with the board they reach, when the cards
  # climb, the target takes the run's top card, and the cells and
  # empty columns can carry it; None when any promise fails. The
  # page plays the moves one by one through Board.apply, every
  # step checked by the rules, exactly as if played by hand
  Web.super_go(b, col, upto, target, Web.super_ok(b, col, upto, target))

def Web.super_moves_go(got: Maybe<&2, Haul>) -> +List<F.Move>:
  # the haul's moves, or nothing at all
  match got:
    case Some{Haul{_, ms}}:
      ms
    case None{}:
      {Nil{} : +List<F.Move>}

def Web.super_moves(w: F.Board, +col: U32, +upto: U32, +target: U32) -> +List<F.Move>:
  # the moves of a supermove, in the order they play — nothing at
  # all when the run cannot cross. The law states these outright,
  # so a supermove may never quietly change its gait
  Web.super_moves_go(Web.supermove(w, col, upto, target))

def Web.super_witness() -> F.Board:
  # a board for the supermove checks: 3♥-4♠-5♦ climbs a column,
  # the six of clubs waits to take them, and the cells are free
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Six{}} <> empty, empty, empty, empty, empty, empty, empty],
    [None{}, None{}, None{}, None{}],
    [0, 0, 0, 0]}

def Web.super_lands() -> F.Board:
  # the board every willing witness with free cells reaches: the
  # run on the six, the source column bare
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [empty,
     F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> (F.Card{F.Clubs{}, F.Six{}} <> empty))),
     empty, empty, empty, empty, empty, empty],
    [None{}, None{}, None{}, None{}],
    [0, 0, 0, 0]}

def Web.stage_witness() -> F.Board:
  # one free cell, and empty columns to stage on: a run of three
  # crosses by parking its lower half on the way
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Six{}} <> empty, empty, empty, empty, empty, empty, empty],
    [Some{F.Card{F.Spades{}, F.Seven{}}}, Some{F.Card{F.Hearts{}, F.Eight{}}}, Some{F.Card{F.Diamonds{}, F.Nine{}}}, None{}],
    [0, 0, 0, 0]}

def Web.stage_lands() -> F.Board:
  # the staged crossing's answer: the run on the six, the one cell
  # still free, the parked cards back in theirs
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [empty,
     F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> (F.Card{F.Clubs{}, F.Six{}} <> empty))),
     empty, empty, empty, empty, empty, empty],
    [Some{F.Card{F.Spades{}, F.Seven{}}}, Some{F.Card{F.Hearts{}, F.Eight{}}}, Some{F.Card{F.Diamonds{}, F.Nine{}}}, None{}],
    [0, 0, 0, 0]}

def Web.crowded_witness() -> F.Board:
  # no free cell, no empty column: nothing bigger than one card
  # can cross, whatever the target wants
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Six{}} <> empty,
     F.Card{F.Spades{}, F.Seven{}} <> empty,
     F.Card{F.Hearts{}, F.Eight{}} <> empty,
     F.Card{F.Diamonds{}, F.Nine{}} <> empty,
     F.Card{F.Clubs{}, F.Ten{}} <> empty,
     F.Card{F.Spades{}, F.Jack{}} <> empty,
     F.Card{F.Hearts{}, F.Queen{}} <> empty],
    [Some{F.Card{F.Clubs{}, F.Ace{}}}, Some{F.Card{F.Diamonds{}, F.Two{}}}, Some{F.Card{F.Clubs{}, F.King{}}}, Some{F.Card{F.Diamonds{}, F.Ace{}}}],
    [0, 0, 0, 0]}

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
    # the supermove vocabulary: a climbing run of three onto a
    # waiting six of clubs crosses in five moves — parked, landed,
    # restacked
    +sup : F.Board = Web.super_witness()
    Web.expect(U32.is_eq(Web.grab(sup, 0), 3), "the witness column should hand over three cards")
    Web.expect(Web.super_check(Web.supermove(sup, 0, 2, 1), Web.super_lands(), 5n),
      "a run of three should cross in five moves onto the six")
    Web.expect(Bool.not(Web.is_some_super(Web.supermove(sup, 0, 1, 1))),
      "a run whose top the target refuses should not move")
    +staged : F.Board = Web.stage_witness()
    Web.expect(Web.super_check(Web.supermove(staged, 0, 2, 1), Web.stage_lands(), 5n),
      "with one free cell, the run should stage on a spare column and cross")
    +crowded : F.Board = Web.crowded_witness()
    Web.expect(Bool.not(Web.is_some_super(Web.supermove(crowded, 0, 2, 1))),
      "no cells and no empty columns should refuse any run")
    IO.print("web api ok\n")
