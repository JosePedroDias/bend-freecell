import Base
import ./freecell.bend as F
import ./solver.bend as S

# ===================================================================
# The plays: the moves beyond single moves, one vocabulary for every
# face of the game.
# ===================================================================
# The rules in freecell.bend take one card at a time. The plays
# build the bigger gestures on top of them: a safe send carries
# every card home the foundations would take without risk, and a
# supermove carries a column's climbing run onto another column in
# one gesture, expanded into the single moves the rules take. The
# browser page, the terminal game and the HTTP server all speak
# these words, and the laws state the gaits outright — so a play
# may never quietly change its steps.
#
# The rules stay the only judge: every move a play expands is
# checked again by Board.apply where it is played, exactly as if
# played by hand. Nothing here knows about pages, terminals or
# sockets — the game is the functions; the faces are the callers.

# --- The board, read plainly --------------------------------------

def Play.piles_of(b: F.Board) -> +List<+List<F.Card>>:
  match b:
    case F.Board{cascades, _, _}:
      cascades

def Play.cells_of(b: F.Board) -> +List<+Maybe<F.Card>>:
  match b:
    case F.Board{_, cells, _}:
      cells

def Play.free_cells(b: F.Board) -> U32:
  # how many cells stand free
  S.Solver.free_count(Play.cells_of(b))

def Play.grab(b: F.Board, col: U32) -> U32:
  # how many cards a column can hand over at once: its rising run,
  # counted from the working card. A card at depth d is grabbable
  # iff d is below this
  F.Pile.run_len(Maybe.default(&2, +List<F.Card>, F.Piles.get(Play.piles_of(b), col), {Nil{} : +List<F.Card>}))

def Play.try_all(ms: +List<F.Move>, got: Maybe<&2, F.Board>) -> Maybe<&2, F.Board>:
  # the moves one by one; the first illegal one ends the line
  match ms got:
    case Nil{} _:
      got
    case _ None{}:
      None{}
    case Con{m, rest} Some{b}:
      Play.try_all(rest, F.Board.apply(b, m))

def Play.counted(ms: +List<F.Move>) -> U32:
  # how many single moves a list holds — the one measure of a play's
  # cost, spent by every face that shows a move count
  U32.from_nat(List.length(&2, F.Move, ms))

def Play.safe(+b: F.Board) -> F.Board & +List<F.Move>:
  # every safe home move, and the board after them
  S.Solver.autoplay(64n, b)

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
# the face plays it.

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

def Play.empties(+piles: +List<+List<F.Card>>, +i: U32, +j: U32, +c: U32) -> U32:
  # how many columns stand empty, besides the source and the target
  match piles:
    case Nil{}:
      0
    case +p <> +ps:
      +x : U32 = Play.empties(ps, i, j, U32.add(c, 1))
      Bool.pick(U32, S.Solver.blank(p) && U32.is_ne(c, i) && U32.is_ne(c, j), (1 + x : U32), x)

def Play.capacity(+b: F.Board, +i: U32, +j: U32) -> U32:
  # how many cards one gesture can carry from i to j: the free
  # cells plus one, doubled once per other empty column
  U32.mul(U32.add(Play.free_cells(b), 1),
    U32.shln(1, U32.to_nat(Play.empties(Play.piles_of(b), i, j, 0))))

def Play.target_pile(b: F.Board, +j: U32) -> +List<F.Card>:
  Maybe.default(&2, +List<F.Card>, F.Piles.get(Play.piles_of(b), j), {Nil{} : +List<F.Card>})

def Play.lands_q(+q: +List<F.Card>, +top: F.Card) -> Bool:
  # the target takes the run's top card: empty, or loaded and
  # accepting it
  match q:
    case Nil{}:
      True{}
    case _ <> _:
      S.Solver.builds_on(q, top)

def Play.lands(b: F.Board, +j: U32, +top: F.Card) -> Bool:
  Play.lands_q(Play.target_pile(b, j), top)

def Play.run_top(+pile: +List<F.Card>, +upto: U32) -> Maybe<&2, F.Card>:
  # the grabbed card: the top of the run that crosses
  List.get(&2, F.Card, pile, U32.to_nat(upto))

def Play.takes_top(b: F.Board, +j: U32, top: Maybe<&2, F.Card>) -> Bool:
  # the target takes the run's top card — or the run is not real
  match top:
    case None{}:
      False{}
    case Some{+t}:
      Play.lands(b, j, t)

def Play.spare(+piles: +List<+List<F.Card>>, +i: U32, +j: U32, +c: U32) -> Maybe<&2, U32>:
  # the first empty column besides the source and the target
  match piles:
    case Nil{}:
      None{}
    case +p <> +ps:
      Bool.pick(Maybe<&2, U32>, S.Solver.blank(p) && U32.is_ne(c, i) && U32.is_ne(c, j),
        Some{c}, Play.spare(ps, i, j, U32.add(c, 1)))

def Play.job_one_go(got: Maybe<&2, F.Board>, +m: F.Move, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  match got:
    case Some{b2}:
      Some{Step{b2, rest, List.append(&2, F.Move, acc, m <> {Nil{} : +List<F.Move>})}}
    case None{}:
      None{}

def Play.job_one(+b: F.Board, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # one card across
  Play.job_one_go(F.Board.apply(b, F.CascadeToCascade{i, j}), F.CascadeToCascade{i, j}, rest, acc)

def Play.job_cells_go(got: Maybe<&2, F.Board>, +ms: +List<F.Move>, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  match got:
    case Some{b2}:
      Some{Step{b2, rest, List.append(&2, F.Move, acc, ms)}}
    case None{}:
      None{}

def Play.job_cells(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # the cells alone can hold all but the top card: the solver's own
  # expansion, replayed move by move on the board
  +ms : +List<F.Move> = S.Solver.expand_super(i, j, c, Play.cells_of(b))
  Play.job_cells_go(Play.try_all(ms, Some{b}), ms, rest, acc)

def Play.job_split_go(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, spare: Maybe<&2, U32>) -> Maybe<&2, Step>:
  match spare:
    case None{}:
      None{}    # cannot happen: the entry's capacity check promised one
    case Some{+e}:
      # the staged half is as large as the remaining emptiness can
      # still carry: (free cells + 1), doubled by the empties the
      # staging column itself leaves
      cap : U32 = U32.mul(U32.add(Play.free_cells(b), 1),
        U32.shln(1, U32.to_nat(U32.sub(Play.empties(Play.piles_of(b), i, j, 0), 1))))
      +m : U32 = U32.min(U32.sub(c, 1), cap)
      +s : U32 = U32.sub(c, m)
      # the lower half stages on e, the rest crosses, the stage
      # follows: three jobs, in that order, ahead of everything
      Some{Step{b, Job{s, i, e} <> (Job{m, i, j} <> (Job{s, e, j} <> rest)), acc}}

def Play.job_split(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # too many cards for the cells alone: a spare empty column
  # stages the lower half
  Play.job_split_go(b, c, i, j, rest, acc, Play.spare(Play.piles_of(b), i, j, 0))

def Play.job_big(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, fits: Bool) -> Maybe<&2, Step>:
  match fits:
    case True{}:
      Play.job_cells(b, c, i, j, rest, acc)
    case False{}:
      Play.job_split(b, c, i, j, rest, acc)

def Play.job_pick(+b: F.Board, +c: U32, +i: U32, +j: U32, +rest: +List<Job>, +acc: +List<F.Move>, one: Bool) -> Maybe<&2, Step>:
  match one:
    case True{}:
      Play.job_one(b, i, j, rest, acc)
    case False{}:
      Play.job_big(b, c, i, j, rest, acc, U32.is_le(U32.sub(c, 1), Play.free_cells(b)))

def Play.job_effect(+b: F.Board, +job: Job, +rest: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Step>:
  # one job's whole effect — the board after its moves, the queue
  # with its children, the moves it spent — with no recursion in
  # it: the trampoline in Play.work does the walking
  match job:
    case Job{+c, +i, +j}:
      Play.job_pick(b, c, i, j, rest, acc, U32.is_eq(c, 1))

def Play.work_done(got: Maybe<&2, Step>,
                   k: F.Board -> +List<Job> -> +List<F.Move> -> Maybe<&2, Haul>) -> Maybe<&2, Haul>:
  match got:
    case Some{Step{+b2, +jobs2, +acc2}}:
      k(b2)(jobs2)(acc2)
    case None{}:
      None{}

def Play.work_step(+b: F.Board, +job: Job, +rest: +List<Job>, +acc: +List<F.Move>,
                   k: F.Board -> +List<Job> -> +List<F.Move> -> Maybe<&2, Haul>) -> Maybe<&2, Haul>:
  # one job, then the caller's continuation: the trampoline step
  Play.work_done(Play.job_effect(b, job, rest, acc), k)

def Play.work(fuel: Nat, +b: F.Board, jobs: +List<Job>, +acc: +List<F.Move>) -> Maybe<&2, Haul>:
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
          Play.work_step(b, job, rest, acc,
            (b2) => (jobs2) => (acc2) => Play.work(p, b2, jobs2, acc2))

def Play.is_some_super(got: Maybe<&2, Haul>) -> Bool:
  # did the run cross?
  match got:
    case Some{_}:
      True{}
    case None{}:
      False{}

def Play.super_check(got: Maybe<&2, Haul>, +want: F.Board, +n: Nat) -> Bool:
  # the run crossed, reached exactly the wanted board, and spent
  # exactly n moves
  match got:
    case None{}:
      False{}
    case Some{Haul{b2, ms}}:
      F.Board.is_eq(b2, want) && Nat.is_eq(List.length(&2, F.Move, ms), n)

def Play.super_ok(+b: F.Board, +col: U32, +upto: U32, +target: U32) -> Bool:
  # every promise a supermove asks, in one answer: the grabbed
  # cards climb from the working card, the target is another column
  # and takes the run's top card, and the cells and empty columns
  # can carry it all
  +pile : +List<F.Card> = Maybe.default(&2, +List<F.Card>, F.Piles.get(Play.piles_of(b), col), {Nil{} : +List<F.Card>})
  run_ok : Bool = U32.is_lt(upto, F.Pile.run_len(pile))
  top : Maybe<&2, F.Card> = Play.run_top(pile, upto)
  U32.is_ne(target, col) && run_ok && Play.takes_top(b, target, top) && U32.is_le(U32.add(upto, 1), Play.capacity(b, col, target))

def Play.super_go(+b: F.Board, +col: U32, +upto: U32, +target: U32, ok: Bool) -> Maybe<&2, Haul>:
  match ok:
    case True{}:
      Play.work(64n, b, Job{U32.add(upto, 1), col, target} <> {Nil{} : +List<Job>}, {Nil{} : +List<F.Move>})
    case False{}:
      None{}

def Play.supermove(+b: F.Board, +col: U32, +upto: U32, +target: U32) -> Maybe<&2, Haul>:
  # the atomic moves of carrying a run — a column's working card
  # and the cards stacked on it, up to the grabbed one — onto
  # another column: Some with the board they reach, when the cards
  # climb, the target takes the run's top card, and the cells and
  # empty columns can carry it; None when any promise fails. The
  # faces play the moves one by one through Board.apply, every
  # step checked by the rules, exactly as if played by hand
  Play.super_go(b, col, upto, target, Play.super_ok(b, col, upto, target))

def Play.super_moves_go(got: Maybe<&2, Haul>) -> +List<F.Move>:
  # the haul's moves, or nothing at all
  match got:
    case Some{Haul{_, ms}}:
      ms
    case None{}:
      {Nil{} : +List<F.Move>}

def Play.super_moves(w: F.Board, +col: U32, +upto: U32, +target: U32) -> +List<F.Move>:
  # the moves of a supermove, in the order they play — nothing at
  # all when the run cannot cross. The law states these outright,
  # so a supermove may never quietly change its gait
  Play.super_moves_go(Play.supermove(w, col, upto, target))

def Play.super_witness() -> F.Board:
  # a board for the supermove checks: 3♥-4♠-5♦ climbs a column,
  # the six of clubs waits to take them, and the cells are free
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Six{}} <> empty, empty, empty, empty, empty, empty, empty],
    [None{}, None{}, None{}, None{}],
    [0, 0, 0, 0]}

def Play.super_lands() -> F.Board:
  # the board every willing witness with free cells reaches: the
  # run on the six, the source column bare
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [empty,
     F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> (F.Card{F.Clubs{}, F.Six{}} <> empty))),
     empty, empty, empty, empty, empty, empty],
    [None{}, None{}, None{}, None{}],
    [0, 0, 0, 0]}

def Play.stage_witness() -> F.Board:
  # one free cell, and empty columns to stage on: a run of three
  # crosses by parking its lower half on the way
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> empty)),
     F.Card{F.Clubs{}, F.Six{}} <> empty, empty, empty, empty, empty, empty, empty],
    [Some{F.Card{F.Spades{}, F.Seven{}}}, Some{F.Card{F.Hearts{}, F.Eight{}}}, Some{F.Card{F.Diamonds{}, F.Nine{}}}, None{}],
    [0, 0, 0, 0]}

def Play.stage_lands() -> F.Board:
  # the staged crossing's answer: the run on the six, the one cell
  # still free, the parked cards back in theirs
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [empty,
     F.Card{F.Hearts{}, F.Three{}} <> (F.Card{F.Spades{}, F.Four{}} <> (F.Card{F.Diamonds{}, F.Five{}} <> (F.Card{F.Clubs{}, F.Six{}} <> empty))),
     empty, empty, empty, empty, empty, empty],
    [Some{F.Card{F.Spades{}, F.Seven{}}}, Some{F.Card{F.Hearts{}, F.Eight{}}}, Some{F.Card{F.Diamonds{}, F.Nine{}}}, None{}],
    [0, 0, 0, 0]}

def Play.crowded_witness() -> F.Board:
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
