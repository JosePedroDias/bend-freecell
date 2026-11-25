import Base
import ./freecell.bend as F

# ===================================================================
# A freecell solver: beam search, after the reference solvers.
# ===================================================================
#   bend solver.bend 7        # prints the moves that solve game 7
#   bend solver.bend 1 | bend terminal-game.bend 1
#
# One level of the beam expands every entry's candidates in
# parallel (Bend's parallel calls), drops boards already seen (a
# Map keyed by one text per board), scores the rest — cards not
# home, plus unsorted cards, plus used cells, plus the home moves
# already made — and keeps the best Beam.width of them. Foundation
# moves are not candidates: after every candidate, the safe home
# moves play themselves. Run moves (supermoves) are candidates,
# expanded into the single moves the rules take.
#
# The whole search is a pure state machine plus one trampoline,
# Beam.tramp, spending one unit of fuel per level: nothing recurses
# freely and no def calls below itself, so the proof gate stays
# green and the solver can carry laws of its own.

# --- The line of play -------------------------------------------

type Trail is Data:
  # a line of moves as shared back-pointers, newest first
  Trail{move: F.Move, rest: Trail}
  Start{}

def Trail.push_list(ms: +List<F.Move>, parent: Trail) -> Trail:
  # a run of moves, in order, in front of everything older
  match ms:
    case Nil{}:
      parent
    case m <> rest:
      Trail.push_list(rest, Trail{m, parent})

def Trail.rev(t: Trail, +acc: +List<F.Move>) -> +List<F.Move>:
  # the trail reversed onto acc
  match t:
    case Start{}:
      acc
    case Trail{move, rest}:
      Trail.rev(rest, move <> acc)

def Trail.finish(t: Trail) -> +List<F.Move>:
  # the whole line, oldest first
  Trail.rev(t, {Nil{} : +List<F.Move>})

# --- The beam ---------------------------------------------------

type Entry is Data:
  # one beam member: where it is, how it got there, how much has
  # gone home on the way — and what it costs to be there, and which
  # key it has in the seen-set. Both are read once, where the entry
  # is born, and never rebuilt
  Entry{board: F.Board, trail: Trail, autos: U32, cost: U32, key: String}

type Search is Data:
  # the beam machine: work to do, a winning line, or no answer
  Beam{entries: +List<Entry>, level: Nat, seen: +Map<Unit>}
  Solved{line: +List<F.Move>}
  Stuck{}

# --- Board keys, for the seen-set -------------------------------

def Key.card_code(c: F.Card) -> U32:
  # a card as one number: 1..52
  match c:
    case F.Card{suit, rank}:
      (1 + F.Suit.to_u32(suit) * 13 + (F.Rank.to_u32(rank) - 1) : U32)

def Key.card_ch(c: F.Card) -> Char:
  # a card as one character: 'B' through 'u', one per card — the
  # same alphabet the cells use. A whole board's key is 68
  # characters, and the sections are fixed where it matters: the
  # foundations are always the last four, the cells the four
  # before them, so the key reads back uniquely
  Char.from_u32(U32.add(65, Key.card_code(c)))

def Key.card_put(c: F.Card, +rest: String) -> String:
  # a card as one character in front of the rest of a key
  SCon{Key.card_ch(c), rest}

def Key.pile(p: +List<F.Card>, +rest: String) -> String:
  # a pile's cards, top first, behind a separator
  match p:
    case Nil{}:
      SCon{'|', rest}
    case c <> cs:
      Key.pile(cs, Key.card_put(c, rest))

def Key.piles(piles: +List<+List<F.Card>>, +rest: String) -> String:
  match piles:
    case Nil{}:
      rest
    case p <> ps:
      Key.piles(ps, Key.pile(p, rest))

def Key.cell_code(c: +Maybe<F.Card>) -> U32:
  # a cell as one number: 0 empty, 1..52 the card
  match c:
    case None{}:
      0
    case Some{card}:
      Key.card_code(card)

def Key.code_ch(n: U32, +rest: String) -> String:
  # a cell code as one character
  SCon{Char.from_u32(U32.add(65, n)), rest}

def Key.cell_codes(cells: +List<+Maybe<F.Card>>, +acc: +List<U32>) -> +List<U32>:
  # the cells' codes, in the order they come
  match cells:
    case Nil{}:
      acc
    case c <> cs:
      Key.cell_codes(cs, Key.cell_code(c) <> acc)

def Key.code_le(a: U32, b: U32) -> Bool:
  # one cell code before another
  U32.is_le(a, b)

def Key.code_list(codes: +List<U32>, +rest: String) -> String:
  # the codes as characters, ascending
  match codes:
    case Nil{}:
      rest
    case c <> cs:
      Key.code_ch(c, Key.code_list(cs, rest))

def Key.cells_sorted(codes: +List<U32>, +rest: String) -> String:
  # the four cells' codes sorted, so that equivalent arrangements
  # share one key
  Key.code_list(List.sort(~U32, ~Key.code_le, codes), rest)

def Key.cells(cells: +List<+Maybe<F.Card>>, +rest: String) -> String:
  # the cells as a sorted set of codes: their order does not matter
  Key.cells_sorted(Key.cell_codes(cells, {Nil{} : +List<U32>}), rest)

def Key.found(n: U32, +rest: String) -> String:
  # a foundation depth as one character
  SCon{Char.from_u32(U32.add(65, n)), rest}

def Key.founds(founds: +List<U32>, +rest: String) -> String:
  match founds:
    case Nil{}:
      rest
    case n <> ns:
      Key.founds(ns, Key.found(n, rest))

def Key.board(b: F.Board) -> String:
  # a board, as one key
  match b:
    case F.Board{cascades, cells, founds}:
      Key.piles(cascades, Key.cells(cells, Key.founds(founds, {SNil{} : String})))

# --- Cost and key, read once -------------------------------------

def Beam.cost_of(b: F.Board, +autos: U32) -> U32:
  # cards not home, plus unsorted cards, plus used cells, plus the
  # home moves already made: the reference solvers' estimate
  match b:
    case F.Board{cascades, cells, founds}:
      unhome = (52 - F.Founds.total(founds) : U32)
      unsorted = F.Piles.unsorted(cascades)
      used = F.Cells.occupied(cells)
      ((unhome + unsorted : U32) + (used + autos : U32) : U32)

def Beam.cost(e: Entry) -> U32:
  # a beam entry's estimate — a field read, not a board walk: the
  # sort asks for it on every comparison
  match e:
    case Entry{_, _, _, +c, _}:
      c

def Beam.key_of(e: Entry) -> String:
  # a beam entry's seen-set key — a field read, not a board walk:
  # the reseed asks for it on every child
  match e:
    case Entry{_, _, _, _, +k}:
      k

# --- The safe home moves ----------------------------------------

def Solver.opposite_min(+founds: +List<U32>, s: F.Suit) -> U32:
  # how deep both foundations opposite in color to s run, at least
  match s:
    case F.Spades{}:
      U32.min(F.Founds.count(founds, 1), F.Founds.count(founds, 2))
    case F.Hearts{}:
      U32.min(F.Founds.count(founds, 0), F.Founds.count(founds, 3))
    case F.Diamonds{}:
      U32.min(F.Founds.count(founds, 0), F.Founds.count(founds, 3))
    case F.Clubs{}:
      U32.min(F.Founds.count(founds, 1), F.Founds.count(founds, 2))

def Solver.safe_ok(+r: U32, opp: U32) -> Bool:
  # aces and twos always go home; a rank r goes once both
  # opposite-color foundations hold r-1, so no build can want it
  U32.is_le(r, 2) || U32.is_ge(opp, (r - 1 : U32))

def Solver.safe_found(founds: +List<U32>, c: F.Card) -> Bool:
  # the conservative rule for sending a card home
  match c:
    case F.Card{suit, rank}:
      Solver.safe_ok(F.Rank.to_u32(rank), Solver.opposite_min(founds, suit))

def Solver.homes(+founds: +List<U32>, +c: F.Card) -> Bool:
  # legal for the foundation, and safe to send there
  F.Founds.takes(founds, c) && Solver.safe_found(founds, c)

def Solver.builds_on(p: +List<F.Card>, c: F.Card) -> Bool:
  # a loaded cascade whose top c can rest on
  match p:
    case Nil{}:
      False{}
    case top <> rest:
      F.Card.can_stack_on(c, top)

# --- Small board facts ------------------------------------------

def Solver.free_count(cells: +List<+Maybe<F.Card>>) -> U32:
  # how many cells are free
  match cells:
    case Nil{}:
      0
    case c <> cs:
      match c:
        case None{}:
          (1 + Solver.free_count(cs) : U32)
        case Some{_}:
          Solver.free_count(cs)

def Solver.first_free(cells: +List<+Maybe<F.Card>>, +i: U32) -> Maybe<&2, U32>:
  # the first free cell's index
  match cells:
    case Nil{}:
      None{}
    case c <> cs:
      match c:
        case None{}:
          Some{i}
        case Some{_}:
          Solver.first_free(cs, U32.add(i, 1))

# --- The autoplay fixpoint --------------------------------------

def Solver.home_cell_pick(ok: Bool, +i: U32, rest: Unit -> Maybe<&2, F.Move>) -> Maybe<&2, F.Move>:
  # a card that goes home, or the rest of the scan
  match ok:
    case True{}:
      Some{F.CellToFoundation{i}}
    case False{}:
      rest(Unit{})

def Solver.home_from_cells(cells: +List<+Maybe<F.Card>>, +founds: +List<U32>, +i: U32) -> Maybe<&2, F.Move>:
  # the first cell card that safely goes home
  match cells:
    case Nil{}:
      None{}
    case c <> cs:
      match c:
        case None{}:
          Solver.home_from_cells(cs, founds, U32.add(i, 1))
        case Some{+card}:
          Solver.home_cell_pick(Solver.homes(founds, card), i, u => Solver.home_from_cells(cs, founds, U32.add(i, 1)))

def Solver.home_pile_pick(ok: Bool, +col: U32, rest: Unit -> Maybe<&2, F.Move>) -> Maybe<&2, F.Move>:
  # a top that goes home, or the rest of the scan
  match ok:
    case True{}:
      Some{F.CascadeToFoundation{col}}
    case False{}:
      rest(Unit{})

def Solver.home_from_piles(piles: +List<+List<F.Card>>, +founds: +List<U32>, +col: U32) -> Maybe<&2, F.Move>:
  # the first cascade top that safely goes home
  match piles:
    case Nil{}:
      None{}
    case p <> ps:
      match p:
        case Nil{}:
          Solver.home_from_piles(ps, founds, U32.add(col, 1))
        case +card <> _:
          Solver.home_pile_pick(Solver.homes(founds, card), col, u => Solver.home_from_piles(ps, founds, U32.add(col, 1)))

def Solver.find_home(b: F.Board) -> Maybe<&2, F.Move>:
  # the first safe home move: out of the cells, then off the tops
  match b:
    case F.Board{+cascades, +cells, +founds}:
      Maybe.or(&2, F.Move, Solver.home_from_cells(cells, founds, 0), Solver.home_from_piles(cascades, founds, 0))

def Solver.autoplay_prepend(pair: F.Board & +List<F.Move>, +m: F.Move) -> F.Board & +List<F.Move>:
  # the home moves that followed m, with m in front
  (b3, more) = pair
  (b3, m <> more)

def Solver.autoplay_apply(got: Maybe<&2, F.Board>, +m: F.Move, +b: F.Board, k: F.Board -> F.Board & +List<F.Move>) -> F.Board & +List<F.Move>:
  # the move was legal: carry on with the new board
  match got:
    case Some{+b2}:
      Solver.autoplay_prepend(k(b2), m)
    case None{}:
      (b, Nil{})

def Solver.autoplay_step(got: Maybe<&2, F.Move>, +b: F.Board, k: F.Board -> F.Board & +List<F.Move>) -> F.Board & +List<F.Move>:
  # a home move to make, or none left
  match got:
    case Some{+m}:
      Solver.autoplay_apply(F.Board.apply(b, m), m, b, k)
    case None{}:
      (b, Nil{})

def Solver.autoplay(fuel: Nat, +b: F.Board) -> F.Board & +List<F.Move>:
  # every safe home move, as long as they come; the closure below
  # is the only recursion, one unit of fuel per move
  match fuel:
    case 0n:
      (b, Nil{})
    case 1n+p:
      Solver.autoplay_step(Solver.find_home(b), b, b2 => Solver.autoplay(p, b2))

# --- Candidates: unparks, run moves, parks ----------------------

def Solver.blank(p: +List<F.Card>) -> Bool:
  # is this column empty
  match p:
    case Nil{}:
      True{}
    case _ <> _:
      False{}

def Solver.cell_take(builds: Bool, blank: Bool, +cell: U32, +col: U32) -> +List<F.Move>:
  # a cell card lands on a loaded column that takes it, or an
  # empty one
  match builds blank:
    case True{} _:
      F.CellToCascade{cell, col} <> {Nil{} : +List<F.Move>}
    case False{} True{}:
      F.CellToCascade{cell, col} <> {Nil{} : +List<F.Move>}
    case _ _:
      Nil{}

def Solver.cell_target(+p: +List<F.Card>, +card: F.Card, +cell: U32, +col: U32) -> +List<F.Move>:
  # one column, as a target for one cell card
  Solver.cell_take(Solver.builds_on(p, card), Solver.blank(p), cell, col)

def Solver.cell_cols(+piles: +List<+List<F.Card>>, +card: F.Card, +cell: U32, +col: U32) -> +List<F.Move>:
  # every column, as a target for one cell card
  match piles:
    case Nil{}:
      Nil{}
    case p <> ps:
      List.append(&2, F.Move, Solver.cell_target(p, card, cell, col), Solver.cell_cols(ps, card, cell, U32.add(col, 1)))

def Solver.wrap(m: F.Move) -> +List<+List<F.Move>>:
  # one move, as a whole candidate of its own
  (m <> {Nil{} : +List<F.Move>}) <> {Nil{} : +List<+List<F.Move>>}

def Solver.wraps(ms: +List<F.Move>) -> +List<+List<F.Move>>:
  # each move, as a candidate of its own
  match ms:
    case Nil{}:
      Nil{}
    case m <> rest:
      List.append(&2, +List<F.Move>, Solver.wrap(m), Solver.wraps(rest))

def Solver.cell_one(c: +Maybe<F.Card>, +piles: +List<+List<F.Card>>, +cell: U32) -> +List<+List<F.Move>>:
  # one cell's card onto every column that takes it
  match c:
    case None{}:
      Nil{}
    case Some{+card}:
      Solver.wraps(Solver.cell_cols(piles, card, cell, 0))

def Solver.cell_moves(cells: +List<+Maybe<F.Card>>, +piles: +List<+List<F.Card>>, +cell: U32) -> +List<+List<F.Move>>:
  # every cell card onto a column that takes it
  match cells:
    case Nil{}:
      Nil{}
    case c <> cs:
      List.append(&2, +List<F.Move>, Solver.cell_one(c, piles, cell), Solver.cell_moves(cs, piles, U32.add(cell, 1)))

def Solver.free_take(cells: +List<+Maybe<F.Card>>, n: Nat, +i: U32, +acc: +List<U32>) -> +List<U32>:
  # the first n free cells, last found first
  match cells:
    case Nil{}:
      acc
    case c <> cs:
      match c:
        case Some{_}:
          match n:
            case 0n:
              acc
            case 1n+q:
              Solver.free_take(cs, 1n+q, U32.add(i, 1), acc)
        case None{}:
          match n:
            case 0n:
              acc
            case 1n+q:
              Solver.free_take(cs, q, U32.add(i, 1), i <> acc)

def Solver.super_parks(+i: U32, frees: +List<U32>) -> +List<F.Move>:
  # the parking half of a run move, first free cell first
  match frees:
    case Nil{}:
      Nil{}
    case f <> fs:
      List.append(&2, F.Move, F.CascadeToCell{i, f} <> {Nil{} : +List<F.Move>}, Solver.super_parks(i, fs))

def Solver.super_unparks(+j: U32, frees: +List<U32>) -> +List<F.Move>:
  # the restacking half of a run move: the last parked card first
  match frees:
    case Nil{}:
      Nil{}
    case f <> fs:
      List.append(&2, F.Move, F.CellToCascade{f, j} <> {Nil{} : +List<F.Move>}, Solver.super_unparks(j, fs))

def Solver.super_join(parks: +List<F.Move>, +i: U32, +j: U32, frees: +List<U32>) -> +List<F.Move>:
  # the parks, the move of the run's deepest card, the restacking
  List.append(&2, F.Move, parks, List.append(&2, F.Move, F.CascadeToCascade{i, j} <> {Nil{} : +List<F.Move>}, Solver.super_unparks(j, frees)))

def Solver.super_build(+revs: +List<U32>, +i: U32, +j: U32) -> +List<F.Move>:
  # the free cells come last found first: the parks go the other way
  Solver.super_join(Solver.super_parks(i, List.reverse(&2, U32, revs)), i, j, revs)

def Solver.expand_super(+i: U32, +j: U32, +k: U32, +cells: +List<+Maybe<F.Card>>) -> +List<F.Move>:
  # a run move as the single moves the rules take: park the top
  # k-1 cards in free cells, move the deepest onto the target,
  # then restack them on it
  Solver.super_build(Solver.free_take(cells, U32.to_nat(U32.sub(k, 1)), 0, Nil{}), i, j)

def Solver.run_take(+p: +List<F.Card>, +free: U32) -> U32:
  # how many cards a column can hand over: its top run, capped by
  # the free cells plus one
  U32.min(F.Pile.run_len(p), (free + 1 : U32))

def Solver.supers_blank(blank: Bool, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32, +j: U32) -> +List<+List<F.Move>>:
  # an empty column takes any run
  match blank:
    case True{}:
      Solver.expand_super(i, j, k, cells) <> {Nil{} : +List<+List<F.Move>>}
    case False{}:
      Nil{}

def Solver.supers_emit(builds: Bool, blank: Bool, +j: U32, +d: F.Card, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # onto a loaded column that takes the run, or an empty one
  match builds:
    case True{}:
      Solver.expand_super(i, j, k, cells) <> {Nil{} : +List<+List<F.Move>>}
    case False{}:
      Solver.supers_blank(blank, k, cells, i, j)

def Solver.supers_land(+q: +List<F.Card>, +j: U32, +d: F.Card, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # one target column
  Solver.supers_emit(Solver.builds_on(q, d), Solver.blank(q), j, d, k, cells, i)

def Solver.supers_pick(other: Bool, q: +List<F.Card>, +j: U32, +d: F.Card, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # onto one column, if it is another one
  match other:
    case False{}:
      Nil{}
    case True{}:
      Solver.supers_land(q, j, d, k, cells, i)

def Solver.supers_target(q: +List<F.Card>, +j: U32, +d: F.Card, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  Solver.supers_pick(U32.is_ne(i, j), q, j, d, k, cells, i)

def Solver.supers_cols(+piles: +List<+List<F.Card>>, +d: F.Card, +k: U32, +cells: +List<+Maybe<F.Card>>, +i: U32, +j: U32) -> +List<+List<F.Move>>:
  # every column, as a target for one run
  match piles:
    case Nil{}:
      Nil{}
    case q <> qs:
      List.append(&2, +List<F.Move>, Solver.supers_target(q, j, d, k, cells, i), Solver.supers_cols(qs, d, k, cells, i, U32.add(j, 1)))

def Solver.supers_deep(deep: Maybe<&2, F.Card>, +k: U32, +piles: +List<+List<F.Card>>, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # the deepest card of the run, and the targets
  match deep:
    case None{}:
      Nil{}
    case Some{+d}:
      Solver.supers_cols(piles, d, k, cells, i, 0)

def Solver.supers_ready(+p: +List<F.Card>, +piles: +List<+List<F.Card>>, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # the run to move, capped by the free cells
  +k = Solver.run_take(p, Solver.free_count(cells))
  Solver.supers_deep(List.get(&2, F.Card, p, U32.to_nat(U32.sub(k, 1))), k, piles, cells, i)

def Solver.supers_one(p: +List<F.Card>, +piles: +List<+List<F.Card>>, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # one column's run, onto every column that takes it
  match p:
    case Nil{}:
      Nil{}
    case top <> rest:
      Solver.supers_ready(p, piles, cells, i)

def Solver.supers(rest: +List<+List<F.Card>>, +piles: +List<+List<F.Card>>, +cells: +List<+Maybe<F.Card>>, +i: U32) -> +List<+List<F.Move>>:
  # every run move, source column by source column. The targets are
  # always the whole board's columns: the scan's own index and the
  # move's target index must count the same list
  match rest:
    case Nil{}:
      Nil{}
    case p <> ps:
      List.append(&2, +List<F.Move>, Solver.supers_one(p, piles, cells, i), Solver.supers(ps, piles, cells, U32.add(i, 1)))

def Solver.parks_col(top: Maybe<&2, F.Card>, +c: U32, +col: U32) -> +List<+List<F.Move>>:
  # one column's top into the first free cell
  match top:
    case Some{_}:
      (F.CascadeToCell{col, c} <> {Nil{} : +List<F.Move>}) <> {Nil{} : +List<+List<F.Move>>}
    case None{}:
      Nil{}

def Solver.parks_cols(+piles: +List<+List<F.Card>>, +c: U32, +col: U32) -> +List<+List<F.Move>>:
  # the columns, one top at a time
  match piles:
    case Nil{}:
      Nil{}
    case p <> ps:
      List.append(&2, +List<F.Move>, Solver.parks_col(List.head(&2, F.Card, p), c, col), Solver.parks_cols(ps, c, U32.add(col, 1)))

def Solver.parks_go(cell: Maybe<&2, U32>, +piles: +List<+List<F.Card>>, +col: U32) -> +List<+List<F.Move>>:
  # into the first free cell, when there is one
  match cell:
    case Some{+c}:
      Solver.parks_cols(piles, c, col)
    case None{}:
      Nil{}

def Solver.parks(+piles: +List<+List<F.Card>>, +cells: +List<+Maybe<F.Card>>, +col: U32) -> +List<+List<F.Move>>:
  # the tops into the first free cell
  Solver.parks_go(Solver.first_free(cells, 0), piles, col)

def Solver.candidates(b: F.Board) -> +List<+List<F.Move>>:
  # unparks, run moves, parks: foundations play themselves
  match b:
    case F.Board{+cascades, +cells, _}:
      List.append(&2, +List<F.Move>, Solver.cell_moves(cells, cascades, 0),
        List.append(&2, +List<F.Move>, Solver.supers(cascades, cascades, cells, 0),
          Solver.parks(cascades, cells, 0)))

# --- Beam expansion, in parallel --------------------------------

def Beam.play_go(got: Maybe<&2, F.Board>, k: F.Board -> Maybe<&2, F.Board>) -> Maybe<&2, F.Board>:
  # a legal move continues through k; an illegal one ends the line
  match got:
    case Some{+b2}:
      k(b2)
    case None{}:
      None{}

def Beam.play(ms: +List<F.Move>, b: F.Board) -> Maybe<&2, F.Board>:
  # apply a candidate's single moves in order
  match ms:
    case Nil{}:
      Some{b}
    case m <> rest:
      Beam.play_go(F.Board.apply(b, m), b2 => Beam.play(rest, b2))

def Beam.child_cons(pair: +List<Entry> & +Map<Unit>, +e: Entry) -> +List<Entry> & +Map<Unit>:
  # a fresh child in front of the rest
  (kids, seen2) = pair
  (e <> kids, seen2)

def Beam.child_present(present: Bool, +e: Entry, +key: String, +seen: +Map<Unit>, cont: +Map<Unit> -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # a board seen before is dropped; a fresh one is kept and marked,
  # by the very key it was sought by
  match present:
    case True{}:
      cont(seen)
    case False{}:
      Beam.child_cons(cont(Map.set(&2, Unit, seen, key, Unit{})), e)

def Beam.child_seen(mr: +Map<Unit> & Bool, +e: Entry, +key: String, +seen: +Map<Unit>, cont: +Map<Unit> -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # the seen-set's answer about a board: a query changes nothing
  (_, present) = mr
  Beam.child_present(present, e, key, seen, cont)

def Beam.child_settled(pair: F.Board & +List<F.Move>, +ms: +List<F.Move>, +trail: Trail, +seen: +Map<Unit>, cont: +Map<Unit> -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # the home moves that followed a candidate belong to its line. The
  # child's cost and key are read here, once — the sort and the
  # reseed read them after, never rebuilt
  (+b3, +more) = pair
  +autos = {U32.from_nat(List.length(&2, F.Move, more)) : U32}
  +key = {Key.board(b3) : String}
  +e = {Entry{b3, Trail.push_list(more, Trail.push_list(ms, trail)), autos, Beam.cost_of(b3, autos), key} : Entry}
  Beam.child_seen(Map.has(&2, Unit, seen, key), e, key, seen, cont)

def Beam.child_step(got: Maybe<&2, F.Board>, +ms: +List<F.Move>, +trail: Trail, +seen: +Map<Unit>, cont: +Map<Unit> -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # one candidate: play it, then the safe home moves; illegal lines
  # end here
  match got:
    case None{}:
      cont(seen)
    case Some{+b2}:
      Beam.child_settled(Solver.autoplay(64n, b2), ms, trail, seen, cont)

def Beam.sprout(cands: +List<+List<F.Move>>, +board: F.Board, +trail: Trail, +seen: +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # every candidate of one beam entry, deduped against the seen-set
  # as it lands: the continuation is the rest of the scan, threaded
  # through the helper defs so no raw list of children ever exists
  match cands:
    case Nil{}:
      (Nil{}, seen)
    case +ms <> rest:
      Beam.child_step(Beam.play(ms, board), ms, trail, seen,
        seen2 => Beam.sprout(rest, board, trail, seen2))

def Beam.children_fresh(e: Entry, +seen: +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # every fresh child of one beam entry
  match e:
    case Entry{+board, +trail, _, _, _}:
      Beam.sprout(Solver.candidates(board), board, trail, seen)

def Beam.join_rest(p2res: +List<Entry> & +Map<Unit>, +kids1: +List<Entry>) -> +List<Entry> & +Map<Unit>:
  # the rest of the level's fresh children, after the first entry's
  (kids2, seen3) = p2res
  (List.append(&2, Entry, kids1, kids2), seen3)

def Beam.join_children(p1: +List<Entry> & +Map<Unit>, p2: +Map<Unit> -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # one entry's fresh children in front of the rest's
  (kids1, seen2) = p1
  Beam.join_rest(p2(seen2), kids1)

def Beam.expand_seq(entries: +List<Entry>, +seen: +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # every fresh child of every entry, deduped as it is made: the
  # seen-set threads through the whole scan, so a board is never
  # built into it twice. The scan of one chunk
  match entries:
    case Nil{}:
      (Nil{}, seen)
    case e <> es:
      Beam.join_children(Beam.children_fresh(e, seen),
        seen2 => Beam.expand_seq(es, seen2))

# --- The level's halves, in parallel ------------------------------

def Beam.half_len(entries: +List<Entry>) -> Nat:
  # where a chunk of entries splits in two
  Nat.div(List.length(&2, Entry, entries), 2n)

def Beam.merge_done(w: +Map<Unit> & +List<Entry>) -> +List<Entry> & +Map<Unit>:
  # the walk's end: the kept children turned right, the grown seen
  (+seen, +acc) = w
  (List.reverse(&2, Entry, acc), seen)

def Beam.merge_pick(present: Bool, +e: Entry, +seen: +Map<Unit>, +acc: +List<Entry>, more: (+Map<Unit> & +List<Entry>) -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # a board the left half never grew is kept, and marked; one it
  # grew is dropped
  match present:
    case True{}:
      more((seen, acc))
    case False{}:
      more((Map.set(&2, Unit, seen, Beam.key_of(e), Unit{}), e <> acc))

def Beam.merge_split(mr: +Map<Unit> & Bool, +e: Entry, +seen: +Map<Unit>, +acc: +List<Entry>, more: (+Map<Unit> & +List<Entry>) -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # the seen-set's answer about the right half's child
  (_, present) = mr
  Beam.merge_pick(present, e, seen, acc, more)

def Beam.merge_seen(w: +Map<Unit> & +List<Entry>, +e: Entry, +es: +List<Entry>, more: (+Map<Unit> & +List<Entry>) -> +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # the world's seen-set asked about one child of the right half
  (+seen, +acc) = w
  Beam.merge_split(Map.has(&2, Unit, seen, Beam.key_of(e)), e, seen, acc, more)

def Beam.merge_walk(kids2: +List<Entry>, w: +Map<Unit> & +List<Entry>) -> +List<Entry> & +Map<Unit>:
  # the right half's children, against the left half's grown seen:
  # fresh ones kept, the seen-set grown by them. The world — the
  # seen-set and the kept children, reversed — travels whole. The
  # recursion is the closure below, on the shorter tail
  match kids2:
    case Nil{}:
      Beam.merge_done(w)
    case +e <> +es:
      Beam.merge_seen(w, e, es, w2 => Beam.merge_walk(es, w2))

def Beam.join_halves(walked: +List<Entry> & +Map<Unit>, +kids1: +List<Entry>) -> +List<Entry> & +Map<Unit>:
  # the left half's children, then the right half's fresh ones, in
  # order; the walk's grown seen is the level's own
  (fresh2, grown) = walked
  (List.append(&2, Entry, kids1, fresh2), grown)

def Beam.merge(r1: +List<Entry> & +Map<Unit>, r2: +List<Entry> & +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # two halves of one level, in order: the right half's children
  # deduped against the left's grown seen — the same boards the one
  # sequential scan would have shunned, in the same order
  (kids1, s1) = r1
  (kids2, _) = r2
  Beam.join_halves(Beam.merge_walk(kids2, (s1, {Nil{} : +List<Entry>})), kids1)

def Beam.split_depth() -> Nat:
  # the most halvings the widest beam takes: 512 entries into
  # 32-entry chunks — 512 / 2^4
  4n

def Beam.fuel_for(+len: Nat) -> Nat:
  # the halvings a beam of len entries takes to fall into ~32-entry
  # chunks: the beam is at most 512 wide, so five answers suffice
  Bool.pick(Nat, Nat.is_le(len, 32n), 0n,
    Bool.pick(Nat, Nat.is_le(len, 64n), 1n,
      Bool.pick(Nat, Nat.is_le(len, 128n), 2n,
        Bool.pick(Nat, Nat.is_le(len, 256n), 3n, Beam.split_depth()))))

def Beam.expand(+fuel: Nat, +entries: +List<Entry>, +seen: +Map<Unit>) -> +List<Entry> & +Map<Unit>:
  # the beam's entries, in halves: both halves expand against the
  # same incoming seen — their work is independent — and their
  # boards meet only in the ordered merge, which keeps exactly the
  # children the one sequential scan would have kept. The fuel is
  # the beam's own width, chosen where the level begins; a chunk
  # that runs out of it expands sequentially. The recursion is the
  # parallel call below — every branch of it has less fuel
  match fuel:
    case 0n:
      Beam.expand_seq(entries, seen)
    case 1n+p:
      r1 r2 = Beam.expand(p, List.take(&2, Entry, entries, Beam.half_len(entries)), seen) Beam.expand(p, List.drop(&2, Entry, entries, Beam.half_len(entries)), seen)
      Beam.merge(r1, r2)

# --- Wins, the width ----------------------------------------------

def Beam.le(a: Entry, b: Entry) -> Bool:
  # cheaper entries first — a field read each way
  U32.is_le(Beam.cost(a), Beam.cost(b))

def Beam.won_if(won: Bool, +e: Entry, rest: Unit -> Maybe<&2, Entry>) -> Maybe<&2, Entry>:
  match won:
    case True{}:
      Some{e}
    case False{}:
      rest(Unit{})

def Beam.find_won(entries: +List<Entry>) -> Maybe<&2, Entry>:
  # the first won entry, if any
  match entries:
    case Nil{}:
      None{}
    case e <> es:
      match e:
        case Entry{+board, _, _, _, _}:
          Beam.won_if(F.Board.is_won(board), e, u => Beam.find_won(es))

def Beam.truncate(sorted: +List<Entry>, +k: Nat) -> +List<Entry>:
  # the first k entries of a sorted list
  match sorted k:
    case _ 0n:
      Nil{}
    case Nil{} _:
      Nil{}
    case e <> es 1n+q:
      e <> Beam.truncate(es, q)

def Beam.width() -> Nat:
  # how many states a level keeps: 256 misses game 12, 1024 doubles
  # the time for the same answers — 512 is the measured middle
  512n

# --- One level --------------------------------------------------

def Beam.reseed(entries: +List<Entry>, seen: +Map<Unit>) -> +Map<Unit>:
  # a level's boards, as the next level's seen-set: the search's
  # memory must stay bounded, so a state can only be shunned for the
  # level after it appears — the reference solvers' window. The
  # keys are the entries' own fields
  match entries:
    case Nil{}:
      seen
    case e <> es:
      Beam.reseed(es, Map.set(&2, Unit, seen, Beam.key_of(e), Unit{}))

def Beam.advance(+kids: +List<Entry>, level: Nat) -> Search:
  # sort by cost, keep the beam, and seed the next level's seen-set
  # with this level's boards
  Beam{Beam.truncate(List.sort(~Entry, ~Beam.le, kids), Beam.width()), level, Beam.reseed(kids, Map.new(&2, Unit))}

def Beam.check(won: Maybe<&2, Entry>, +kids: +List<Entry>, level: Nat) -> Search:
  # a won child solves the game
  match won:
    case Some{e}:
      match e:
        case Entry{_, +trail, _, _, _}:
          Solved{Trail.finish(trail)}
    case None{}:
      Beam.advance(kids, level)

def Beam.collect(pair: +List<Entry> & +Map<Unit>, level: Nat) -> Search:
  # the fresh children: watch for a win
  (+kids, _) = pair
  Beam.check(Beam.find_won(kids), kids, level)

def Beam.level(+entries: +List<Entry>, level: Nat, +seen: +Map<Unit>) -> Search:
  # expand in parallel halves — the fuel from the beam's own width —
  # sort, truncate: one level of the beam
  Beam.collect(Beam.expand(Beam.fuel_for(List.length(&2, Entry, entries)), entries, seen), level)

def Beam.go(entries: +List<Entry>, level: Nat, +seen: +Map<Unit>) -> Search:
  # out of levels or entries: stuck
  match entries level:
    case Nil{} _:
      Stuck{}
    case _ 0n:
      Stuck{}
    case e <> es 1n+p:
      Beam.level(e <> es, p, seen)

def Beam.step(m: Search) -> Search:
  # one beam level
  match m:
    case Solved{+line}:
      Solved{line}
    case Stuck{}:
      Stuck{}
    case Beam{entries, level, seen}:
      Beam.go(entries, level, seen)

def Beam.tramp(fuel: Nat, m: Search) -> Search:
  # one level per unit of fuel: the search's only freely-recursive
  # def, and every level spends one unit
  match fuel m:
    case _ Solved{+line}:
      Solved{line}
    case _ Stuck{}:
      Stuck{}
    case 0n Beam{_, _, _}:
      Stuck{}
    case 1n+p Beam{_, _, _}:
      Beam.tramp(p, Beam.step(m))

# --- The entry --------------------------------------------------

def Solver.first(autod: F.Board & +List<F.Move>, levels: Nat) -> Search:
  # the search's opening state: the root entry in a one-wide beam,
  # the level budget full. The opening home moves belong to the
  # line; the root's cost counts none of them, as it always has.
  # A driver that steps this state with Beam.step walks the very
  # search Beam.tramp would run — the browser page does exactly
  # that, one level per frame gap
  (+b2, autos) = autod
  +root = {Entry{b2, Trail.push_list(autos, Start{}), 0, Beam.cost_of(b2, 0), Key.board(b2)} : Entry}
  Beam{root <> {Nil{} : +List<Entry>}, levels, Map.set(&2, Unit, Map.new(&2, Unit), Beam.key_of(root), Unit{})}

def Solver.begin(autod: F.Board & +List<F.Move>, +levels: Nat) -> Search:
  # the whole search: the opening state, run to its answer
  Beam.tramp(levels, Solver.first(autod, levels))

def Solver.solve(levels: Nat, board: F.Board) -> Search:
  # beam-search a board with a level budget
  Solver.begin(Solver.autoplay(64n, board), levels)

# --- The hint: a shallow search's opener ---------------------------

def Solver.hint_levels() -> Nat:
  # how deep the hint looks: a couple of levels of the beam, not
  # the whole solve — deep enough to see past a move's face, at a
  # fraction of the search's cost
  3n

def Solver.entry_opener(e: Entry) -> Maybe<&2, F.Move>:
  # an entry's opening move: the oldest in its trail, the first it
  # would play
  match e:
    case Entry{_, +trail, _, _, _}:
      List.head(&2, F.Move, Trail.finish(trail))

def Solver.head_opener(got: Maybe<&2, Entry>) -> Maybe<&2, F.Move>:
  # the beam's best entry, asked for its opener
  match got:
    case Some{+e}:
      Solver.entry_opener(e)
    case None{}:
      None{}

def Solver.opener(m: Search) -> Maybe<&2, F.Move>:
  # the move a search's answer opens with: the winning line's
  # first move when it solved, the best entry's when it still
  # beams, nothing when it is stuck
  match m:
    case Solved{+line}:
      List.head(&2, F.Move, line)
    case Beam{+entries, _, _}:
      Solver.head_opener(List.head(&2, Entry, entries))
    case Stuck{}:
      None{}

def Solver.hint_witness() -> F.Board:
  # four cards short of a win: the kings and queens of spades and
  # hearts in one column over full club and diamond foundations —
  # nothing autoplay-safe at the top, so every line opens by
  # moving the king of spades
  +empty : +List<F.Card> = {Nil{} : +List<F.Card>}
  F.Board{
    [F.Card{F.Spades{}, F.King{}} <> (F.Card{F.Spades{}, F.Queen{}} <> (F.Card{F.Hearts{}, F.King{}} <> (F.Card{F.Hearts{}, F.Queen{}} <> empty))),
     empty, empty, empty, empty, empty, empty, empty],
    [None{}, None{}, None{}, None{}],
    [11, 11, 13, 13]}

# --- The report -------------------------------------------------

def Solve.col_word(n: U32) -> String:
  # a column index as typed
  Char.show(Char.from_u32(U32.add(49, n)))

def Solve.cell_word(n: U32) -> String:
  # a cell index as typed
  Char.show(Char.from_u32(U32.add(97, n)))

def Solve.found_word(n: U32) -> String:
  # a foundation index as typed, when a home card comes back down
  Char.show(Char.from_u32(U32.add(101, n)))

def Solve.word(m: F.Move) -> String:
  # a move in the words the terminal game takes
  match m:
    case F.CascadeToCell{col, cell}:
      Solve.col_word(col) ++ " " ++ Solve.cell_word(cell)
    case F.CascadeToCascade{col, col2}:
      Solve.col_word(col) ++ " " ++ Solve.col_word(col2)
    case F.CascadeToFoundation{col}:
      Solve.col_word(col) ++ " h"
    case F.CellToCascade{cell, col}:
      Solve.cell_word(cell) ++ " " ++ Solve.col_word(col)
    case F.CellToFoundation{cell}:
      Solve.cell_word(cell) ++ " h"
    case F.FoundationToCascade{found, col}:
      Solve.found_word(found) ++ " " ++ Solve.col_word(col)

def Solve.count(ms: +List<F.Move>) -> U32:
  # how long a line is
  U32.from_nat(List.length(&2, F.Move, ms))

def Solve.listing(ms: +List<F.Move>) -> IO(Unit):
  # the line, one move a line, as the terminal game takes them
  match ms:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case m <> rest:
      do IO<Unit>:
        IO.print(Solve.word(m) ++ "\n")
        Solve.listing(rest)

def Solve.check(ms: +List<F.Move>, got: Maybe<&2, F.Board>) -> Bool:
  # does playing the rest of the line on the pending board win?
  # An illegal move fails the line; the last board must be won
  match ms got:
    case _ None{}:
      False{}
    case Nil{} Some{+b2}:
      F.Board.is_won(b2)
    case Con{+m, +rest} Some{+b2}:
      Solve.check(rest, F.Board.apply(b2, m))

def Solve.check_line(board: F.Board, ms: +List<F.Move>) -> Bool:
  # a line of play wins when every move is legal and the last
  # board is won
  Solve.check(ms, Some{board})

def Solve.solved_of(m: Search, board: F.Board) -> Bool:
  # the search's answer, checked against the board it came from
  match m:
    case Solved{+moves}:
      Solve.check_line(board, moves)
    case _:
      False{}

def Solve.verified(+game: U32) -> Bool:
  # does the search find a line that really wins?
  Solve.solved_of(Solver.solve(200n, F.Board.deal_ms(game)), F.Board.deal_ms(game))

def Solve.report(m: Search, +game: U32) -> IO(Unit):
  # say what the search found, and say it only between the moves
  match m:
    case Solved{+moves}:
      do IO<Unit>:
        IO.print_err("game " ++ U32.show(game) ++ " solves in " ++ U32.show(Solve.count(moves)) ++ " moves, verified: " ++ Bool.show(Solve.check_line(F.Board.deal_ms(game), moves)) ++ "\n")
        Solve.listing(moves)
    case _:
      do IO<Unit>:
        IO.print_err("no solution found within the beam budgets\n")

def Solve.args_game(args: List<String>) -> Maybe<&2, U32>:
  # the game number asked for on the command line, if any
  match args:
    case Con{_, Con{a, _}}:
      U32.read(a)
    case _:
      None{}

def Solve.seed(got: Maybe<&2, U32>) -> U32:
  # the game to solve: the one asked for, or game 1
  match got:
    case Some{n}:
      n
    case None{}:
      1

def Solve.run(+game: U32) -> IO(Unit):
  # solve one game and print its line
  do IO<Unit>:
    IO.print_err("solving game " ++ U32.show(game) ++ "...\n")
    Solve.report(Solver.solve(200n, F.Board.deal_ms(game)), game)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Solve.run(Solve.seed(Solve.args_game(args)))
