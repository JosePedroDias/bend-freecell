import Base

# ===================================================================
# Freecell, abstractly: the rules of the game as pure functions.
# ===================================================================
# A deck has 4 suits of 13 cards. A board has 8 cascades (the top
# card of a cascade is the head of its list), 4 free cells and 4
# foundations, one per suit: a foundation with count n holds the
# cards of its suit with rank 1 (the Ace) through rank n.
#
# The rules, in one place:
#   - the top card of a cascade may move to a free cell
#   - a card may rest on a cascade card exactly one rank higher of
#     the opposite color; an empty cascade takes any card
#   - a card may move to its suit's foundation only as the next
#     rank up: the Ace starts an empty one
#   - the top card of a foundation may come back down to a cascade
#     the same rules would take it onto: the foundations are a
#     home, not a trap
#   - the game is won when every foundation holds all 13 cards
#
# Board.move_ok checks a move against these rules, Board.force
# performs it unchecked, and Board.apply is the two combined: the
# authoritative, checked transition. Multi-card moves (supermoves)
# are sequences of single moves, so the rules here are complete.

# --- Colors and suits -------------------------------------------

type Color is Data:
  Black{}
  Red{}

type Suit is Data:
  Spades{}
  Hearts{}
  Diamonds{}
  Clubs{}

def Suit.color(s: Suit) -> Color:
  match s:
    case Spades{}:
      Black{}
    case Clubs{}:
      Black{}
    case Hearts{}:
      Red{}
    case Diamonds{}:
      Red{}

def Suit.is_red(s: Suit) -> Bool:
  # hearts and diamonds are red, spades and clubs black
  match s:
    case Spades{}:
      False{}
    case Clubs{}:
      False{}
    case Hearts{}:
      True{}
    case Diamonds{}:
      True{}

def Suit.to_u32(s: Suit) -> U32:
  # the foundation of a suit: spades 0, hearts 1, clubs 2, diamonds 3
  # — an order that alternates the colors down the row: S H C D
  match s:
    case Spades{}:
      0
    case Hearts{}:
      1
    case Clubs{}:
      2
    case Diamonds{}:
      3

def Suit.all() -> +List<Suit>:
  # the four suits in foundation order — the inverse of Suit.to_u32
  [Spades{}, Hearts{}, Clubs{}, Diamonds{}]

def Suit.show(s: Suit) -> String:
  match s:
    case Spades{}:
      "S"
    case Hearts{}:
      "H"
    case Diamonds{}:
      "D"
    case Clubs{}:
      "C"

def Suit.is_eq(a: Suit, b: Suit) -> Bool:
  # the same suit
  match a b:
    case Spades{} Spades{}:
      True{}
    case Hearts{} Hearts{}:
      True{}
    case Diamonds{} Diamonds{}:
      True{}
    case Clubs{} Clubs{}:
      True{}
    case _ _:
      False{}

# --- Ranks ------------------------------------------------------

type Rank is Data:
  Ace{}
  Two{}
  Three{}
  Four{}
  Five{}
  Six{}
  Seven{}
  Eight{}
  Nine{}
  Ten{}
  Jack{}
  Queen{}
  King{}

def Rank.to_u32(r: Rank) -> U32:
  # the Ace is 1, the King 13
  match r:
    case Ace{}:
      1
    case Two{}:
      2
    case Three{}:
      3
    case Four{}:
      4
    case Five{}:
      5
    case Six{}:
      6
    case Seven{}:
      7
    case Eight{}:
      8
    case Nine{}:
      9
    case Ten{}:
      10
    case Jack{}:
      11
    case Queen{}:
      12
    case King{}:
      13

def Rank.show(r: Rank) -> String:
  match r:
    case Ace{}:
      "A"
    case Two{}:
      "2"
    case Three{}:
      "3"
    case Four{}:
      "4"
    case Five{}:
      "5"
    case Six{}:
      "6"
    case Seven{}:
      "7"
    case Eight{}:
      "8"
    case Nine{}:
      "9"
    case Ten{}:
      "T"
    case Jack{}:
      "J"
    case Queen{}:
      "Q"
    case King{}:
      "K"

def Rank.all() -> +List<Rank>:
  # the Ace to the King, in order
  [Ace{}, Two{}, Three{}, Four{}, Five{}, Six{}, Seven{}, Eight{}, Nine{}, Ten{}, Jack{}, Queen{}, King{}]

def Rank.is_one_below(low: Rank, high: Rank) -> Bool:
  # low sits directly under high in rank
  U32.is_eq((Rank.to_u32(low) + 1 : U32), Rank.to_u32(high))

def Rank.is_eq(a: Rank, b: Rank) -> Bool:
  # the same rank
  match a b:
    case Ace{} Ace{}:
      True{}
    case Two{} Two{}:
      True{}
    case Three{} Three{}:
      True{}
    case Four{} Four{}:
      True{}
    case Five{} Five{}:
      True{}
    case Six{} Six{}:
      True{}
    case Seven{} Seven{}:
      True{}
    case Eight{} Eight{}:
      True{}
    case Nine{} Nine{}:
      True{}
    case Ten{} Ten{}:
      True{}
    case Jack{} Jack{}:
      True{}
    case Queen{} Queen{}:
      True{}
    case King{} King{}:
      True{}
    case _ _:
      False{}

# --- Cards ------------------------------------------------------

type Card is Data:
  Card{suit: Suit, rank: Rank}

def Card.show(c: Card) -> String:
  # rank then suit, as in "QS"
  match c:
    case Card{suit, rank}:
      Rank.show(rank) ++ Suit.show(suit)

def Card.suit_idx(c: Card) -> U32:
  # the foundation this card belongs to
  match c:
    case Card{suit, _}:
      Suit.to_u32(suit)

def Card.is_eq(a: Card, b: Card) -> Bool:
  # the same suit and rank
  match a b:
    case Card{suit, rank} Card{suit2, rank2}:
      Suit.is_eq(suit, suit2) && Rank.is_eq(rank, rank2)

def Card.can_stack_on(card: Card, onto: Card) -> Bool:
  # the cascade rule: card may rest on onto — exactly one rank
  # lower, and of the opposite color
  match card onto:
    case Card{suit, rank} Card{suit2, rank2}:
      one_below = Rank.is_one_below(rank, rank2)
      alternating = Bool.xor(Suit.is_red(suit), Suit.is_red(suit2))
      one_below && alternating

# --- Moves ------------------------------------------------------

# A move takes one card from the top of a cascade, from a cell, or
# off the top of a foundation, and drops it on a cell, a cascade or
# its foundation.
type Move is Data:
  CascadeToCell{col: U32, cell: U32}
  CascadeToCascade{col: U32, col2: U32}
  CascadeToFoundation{col: U32}
  CellToCascade{cell: U32, col: U32}
  CellToFoundation{cell: U32}
  FoundationToCascade{found: U32, col: U32}

# a rule that must hold: None when it fails
def check(ok: Bool) -> Maybe<&2, Unit>:
  match ok:
    case True{}:
      Some{Unit{}}
    case False{}:
      None{}

# --- Cascades ---------------------------------------------------
# A cascade is a list of cards with its top card at the head.

def Piles.get(piles: +List<+List<Card>>, i: U32) -> Maybe<&2, +List<Card>>:
  # cascade i, if it exists (0 <= i < 8 on a standard board)
  List.get(&2, +List<Card>, piles, U32.to_nat(i))

def Piles.set(piles: +List<+List<Card>>, i: U32, p: +List<Card>) -> +List<+List<Card>>:
  List.set(&2, +List<Card>, piles, U32.to_nat(i), p)

def Piles.top_of(got: Maybe<&2, +List<Card>>) -> Maybe<&2, Card>:
  # the top card of a cascade that may be missing: its head, if any
  match got:
    case Some{p}:
      List.head(&2, Card, p)
    case None{}:
      None{}

def Piles.accepts(got: Maybe<&2, +List<Card>>, c: Card) -> Bool:
  # the cascade rule for a target: an empty cascade takes any card,
  # a loaded one takes c only if c stacks on its top
  match got:
    case Some{p}:
      match p:
        case Nil{}:
          True{}
        case top <> rest:
          Card.can_stack_on(c, top)
    case None{}:
      False{}

def Piles.pop_top.go(got: Maybe<&2, +List<Card>>, piles: +List<+List<Card>>, i: U32) -> +List<+List<Card>>:
  # remove the top card of cascade i, if there is one
  match got:
    case Some{p}:
      match p:
        case Nil{}:
          piles
        case top <> rest:
          Piles.set(piles, i, rest)
    case None{}:
      piles

def Piles.pop_top(+piles: +List<+List<Card>>, +i: U32) -> +List<+List<Card>>:
  Piles.pop_top.go(Piles.get(piles, i), piles, i)

def Piles.push_top.go(got: Maybe<&2, +List<Card>>, piles: +List<+List<Card>>, i: U32, c: Card) -> +List<+List<Card>>:
  # put c on top of cascade i, if that cascade exists
  match got:
    case Some{p}:
      Piles.set(piles, i, c <> p)
    case None{}:
      piles

def Piles.push_top(+piles: +List<+List<Card>>, +i: U32, c: Card) -> +List<+List<Card>>:
  Piles.push_top.go(Piles.get(piles, i), piles, i, c)

def Piles.put_top(got: Maybe<&2, Card>, piles: +List<+List<Card>>, i: U32) -> +List<+List<Card>>:
  # a taken card (if any) goes on top of cascade i
  match got:
    case Some{c}:
      Piles.push_top(piles, i, c)
    case None{}:
      piles

def Piles.card_count(piles: +List<+List<Card>>) -> U32:
  # how many cards sit on the cascades
  match piles:
    case Nil{}:
      0
    case p <> ps:
      (U32.from_nat(List.length(&2, Card, p)) + Piles.card_count(ps) : U32)

def Pile.is_eq(a: +List<Card>, b: +List<Card>) -> Bool:
  # the same cards in the same order
  match a b:
    case Nil{} Nil{}:
      True{}
    case h <> t h2 <> t2:
      Card.is_eq(h, h2) && Pile.is_eq(t, t2)
    case _ _:
      False{}

def Piles.is_eq(a: +List<+List<Card>>, b: +List<+List<Card>>) -> Bool:
  # the same cascades
  match a b:
    case Nil{} Nil{}:
      True{}
    case p <> ps p2 <> ps2:
      Pile.is_eq(p, p2) && Piles.is_eq(ps, ps2)
    case _ _:
      False{}

def Pile.run_if(ok: Bool, +acc: U32, k: Unit -> U32) -> U32:
  # a run continues through k, or stops at acc cards
  match ok:
    case True{}:
      k(Unit{})
    case False{}:
      acc

def Pile.run_go(rest: +List<Card>, top: Card, +acc: U32) -> U32:
  # the run counts acc cards so far, its newest on top
  match rest:
    case Nil{}:
      acc
    case +next <> more:
      Pile.run_if(Card.can_stack_on(top, next), acc, u => Pile.run_go(more, next, (acc + 1 : U32)))

def Pile.run_len(p: +List<Card>) -> U32:
  # how many cards from the top form a descending, alternating run
  match p:
    case Nil{}:
      0
    case top <> rest:
      Pile.run_go(rest, top, 1)

def Piles.unsorted(piles: +List<+List<Card>>) -> U32:
  # how many cards sit outside their column's top run: the disorder
  match piles:
    case Nil{}:
      0
    case +p <> ps:
      (U32.sub(U32.from_nat(List.length(&2, Card, p)), Pile.run_len(p)) + Piles.unsorted(ps) : U32)

# --- Free cells -------------------------------------------------

def Cells.get(cells: +List<+Maybe<Card>>, i: U32) -> Maybe<&2, +Maybe<Card>>:
  # cell i, if it exists (0 <= i < 4 on a standard board)
  List.get(&2, +Maybe<Card>, cells, U32.to_nat(i))

def Cells.card_of(got: Maybe<&2, +Maybe<Card>>) -> Maybe<&2, Card>:
  # the card in a cell that may be missing, if the cell holds one
  match got:
    case Some{m}:
      match m:
        case Some{c}:
          Some{c}
        case None{}:
          None{}
    case None{}:
      None{}

def Cells.card(cells: +List<+Maybe<Card>>, i: U32) -> Maybe<&2, Card>:
  Cells.card_of(Cells.get(cells, i))

def Cells.is_free_of(got: Maybe<&2, +Maybe<Card>>) -> Bool:
  # a cell that exists (its index is in bounds) and is empty
  match got:
    case Some{m}:
      match m:
        case None{}:
          True{}
        case Some{_}:
          False{}
    case None{}:
      False{}

def Cells.is_free(cells: +List<+Maybe<Card>>, i: U32) -> Bool:
  Cells.is_free_of(Cells.get(cells, i))

def Cells.put.go(got: Maybe<&2, +Maybe<Card>>, cells: +List<+Maybe<Card>>, i: U32, c: Card) -> +List<+Maybe<Card>>:
  # put c into cell i, if that cell exists
  match got:
    case Some{_}:
      List.set(&2, +Maybe<Card>, cells, U32.to_nat(i), Some{c})
    case None{}:
      cells

def Cells.put(+cells: +List<+Maybe<Card>>, +i: U32, c: Card) -> +List<+Maybe<Card>>:
  Cells.put.go(Cells.get(cells, i), cells, i, c)

def Cells.put_card(got: Maybe<&2, Card>, cells: +List<+Maybe<Card>>, i: U32) -> +List<+Maybe<Card>>:
  # a taken card (if any) lands in cell i
  match got:
    case Some{c}:
      Cells.put(cells, i, c)
    case None{}:
      cells

def Cells.clear.go(got: Maybe<&2, +Maybe<Card>>, cells: +List<+Maybe<Card>>, i: U32) -> +List<+Maybe<Card>>:
  # empty cell i, if that cell exists
  match got:
    case Some{_}:
      List.set(&2, +Maybe<Card>, cells, U32.to_nat(i), None{})
    case None{}:
      cells

def Cells.clear(+cells: +List<+Maybe<Card>>, +i: U32) -> +List<+Maybe<Card>>:
  Cells.clear.go(Cells.get(cells, i), cells, i)

def Cells.occupied(cells: +List<+Maybe<Card>>) -> U32:
  # how many cards sit in the cells
  match cells:
    case Nil{}:
      0
    case c <> cs:
      match c:
        case Some{_}:
          (1 + Cells.occupied(cs) : U32)
        case None{}:
          Cells.occupied(cs)

def Cells.slot_eq(a: +Maybe<Card>, b: +Maybe<Card>) -> Bool:
  # the same card, or the same emptiness
  match a b:
    case None{} None{}:
      True{}
    case Some{c} Some{c2}:
      Card.is_eq(c, c2)
    case _ _:
      False{}

def Cells.is_eq(a: +List<+Maybe<Card>>, b: +List<+Maybe<Card>>) -> Bool:
  # the same cells
  match a b:
    case Nil{} Nil{}:
      True{}
    case c <> cs c2 <> cs2:
      Cells.slot_eq(c, c2) && Cells.is_eq(cs, cs2)
    case _ _:
      False{}

# --- Foundations ------------------------------------------------
# A foundation is a count: the spade foundation with count n holds
# the spade Ace through the spade of rank n.

def Founds.get(founds: +List<U32>, i: U32) -> Maybe<&2, U32>:
  # the count of foundation i, if it exists
  List.get(&2, U32, founds, U32.to_nat(i))

def Founds.count(founds: +List<U32>, i: U32) -> U32:
  # how deep foundation i runs, 0 when it is missing
  Maybe.default(&2, U32, Founds.get(founds, i), 0)

def Founds.next_ok(got: Maybe<&2, U32>, rank: Rank) -> Bool:
  # the foundation rule: a foundation that holds n cards takes the
  # card of rank n + 1 next — so the Ace starts an empty one
  match got:
    case Some{count}:
      U32.is_eq(Rank.to_u32(rank), (count + 1 : U32))
    case None{}:
      False{}

def Founds.of_suit(founds: +List<U32>, s: Suit) -> Maybe<&2, U32>:
  Founds.get(founds, Suit.to_u32(s))

def Founds.takes(founds: +List<U32>, c: Card) -> Bool:
  # the foundation of c's suit takes c next
  match c:
    case Card{suit, rank}:
      Founds.next_ok(Founds.of_suit(founds, suit), rank)

def Founds.top_card.mk(s: Suit, got: Maybe<&2, Rank>) -> Maybe<&2, Card>:
  # the card of the suit and the rank, when the rank is real
  match got:
    case Some{rank}:
      Some{Card{s, rank}}
    case None{}:
      None{}

def Founds.top_card.pick(s: Suit, ok: Bool, +n: U32) -> Maybe<&2, Card>:
  # a positive count names its rank; a count of zero names nothing
  match ok:
    case True{}:
      Founds.top_card.mk(s, List.get(&2, Rank, Rank.all(), U32.to_nat(U32.sub(n, 1))))
    case False{}:
      None{}

def Founds.top_card.rank(s: Suit, got: Maybe<&2, U32>) -> Maybe<&2, Card>:
  # the foundation's top card, once its suit is known
  match got:
    case Some{+n}:
      Founds.top_card.pick(s, U32.is_lt(0, n), n)
    case None{}:
      None{}

def Founds.top_card.go(suit: Maybe<&2, Suit>, founds: +List<U32>, +i: U32) -> Maybe<&2, Card>:
  # the suit must be a foundation's, and the foundation must exist
  match suit:
    case Some{s}:
      Founds.top_card.rank(s, Founds.get(founds, i))
    case None{}:
      None{}

def Founds.top_card(founds: +List<U32>, +i: U32) -> Maybe<&2, Card>:
  # the card on top of foundation i — its suit's card of its count —
  # or None when the foundation is missing or holds nothing. The
  # pull moves this card, and only this card, back down
  Founds.top_card.go(List.get(&2, Suit, Suit.all(), U32.to_nat(i)), founds, i)

def Founds.inc.go(got: Maybe<&2, U32>, founds: +List<U32>, i: U32) -> +List<U32>:
  # add one card to foundation i, if it exists
  match got:
    case Some{count}:
      List.set(&2, U32, founds, U32.to_nat(i), (count + 1 : U32))
    case None{}:
      founds

def Founds.inc(+founds: +List<U32>, +i: U32) -> +List<U32>:
  Founds.inc.go(Founds.get(founds, i), founds, i)

def Founds.inc_card(got: Maybe<&2, Card>, founds: +List<U32>) -> +List<U32>:
  # a taken card (if any) lands on its foundation
  match got:
    case Some{c}:
      Founds.inc(founds, Card.suit_idx(c))
    case None{}:
      founds

def Founds.dec.go(got: Maybe<&2, U32>, founds: +List<U32>, i: U32) -> +List<U32>:
  # take one card back off foundation i, if it exists
  match got:
    case Some{count}:
      List.set(&2, U32, founds, U32.to_nat(i), U32.sub(count, 1))
    case None{}:
      founds

def Founds.dec(+founds: +List<U32>, +i: U32) -> +List<U32>:
  # the mirror of Founds.inc: a pulled card leaves its foundation.
  # Assumes the foundation holds one, as Board.move_ok checked
  Founds.dec.go(Founds.get(founds, i), founds, i)

def Founds.total(founds: +List<U32>) -> U32:
  # how many cards sit on the foundations
  match founds:
    case Nil{}:
      0
    case n <> ns:
      (n + Founds.total(ns) : U32)

def Founds.is_eq(a: +List<U32>, b: +List<U32>) -> Bool:
  # the same foundations
  match a b:
    case Nil{} Nil{}:
      True{}
    case n <> ns n2 <> ns2:
      U32.is_eq(n, n2) && Founds.is_eq(ns, ns2)
    case _ _:
      False{}

# --- The board --------------------------------------------------

type Board is Data:
  Board{cascades: List<&2, List<&2, Card>>, cells: List<&2, Maybe<&2, Card>>, founds: List<&2, U32>}

def Board.empty() -> Board:
  # 8 empty cascades, 4 empty cells, 4 empty foundations
  Board{List.replicate(+List<Card>, 8n, Nil{}), List.replicate(+Maybe<Card>, 4n, None{}), List.replicate(U32, 4n, 0)}

def Deck.suit_cards(+s: Suit, ranks: +List<Rank>) -> +List<Card>:
  # every card of one suit, in rank order
  match ranks:
    case Nil{}:
      Nil{}
    case r <> rs:
      Card{s, r} <> Deck.suit_cards(s, rs)

def Deck.new() -> +List<Card>:
  # the whole deck: spades, hearts, diamonds, clubs
  a b c d = Deck.suit_cards(Spades{}, Rank.all()) Deck.suit_cards(Hearts{}, Rank.all()) Deck.suit_cards(Diamonds{}, Rank.all()) Deck.suit_cards(Clubs{}, Rank.all())
  List.concat(&2, Card, a <> (b <> (c <> (d <> {Nil{} : +List<+List<Card>>}))))

def Deal.go(deck: +List<Card>, piles: +List<+List<Card>>, +i: U32) -> +List<+List<Card>>:
  # deal the deck round-robin: card j lands on cascade j mod 8
  match deck:
    case Nil{}:
      piles
    case c <> cs:
      Deal.go(cs, Piles.push_top(piles, i, c), U32.mod((i + 1 : U32), 8))

def Board.deal(deck: +List<Card>) -> Board:
  # a fresh deal: every card dealt face up onto an empty board
  Board{Deal.go(deck, List.replicate(+List<Card>, 8n, Nil{}), 0), List.replicate(+Maybe<Card>, 4n, None{}), List.replicate(U32, 4n, 0)}

# --- The Microsoft deal ----------------------------------------
# The classic game numbers: a seeded generator picks the cards.
# One round: state' = (214013 * state + 2531011) & 0x7fffffff,
# rand = state' >> 16; the rand-th of the remaining cards is dealt,
# and the last remaining card fills its slot. Game 1 opens with
# JD 2D 9H JC 5D 7H 7C 5H, as published.

def Deck.at(xs: +List<Card>, n: Nat, d: Card) -> Card:
  # the card at n, or d once n runs past the end
  Maybe.default(&2, Card, List.get(&2, Card, xs, n), d)

def MS.next(state: U32) -> U32:
  # one round of the Microsoft generator: the next 31-bit state
  U32.and(U32.add(U32.mul(state, 214013), 2531011), 2147483647)

def MS.suits() -> +List<Suit>:
  # the suit order behind card i's i % 4: clubs, diamonds, hearts, spades
  [Clubs{}, Diamonds{}, Hearts{}, Spades{}]

def MS.rank_suits(+r: Rank, +suits: +List<Suit>) -> +List<Card>:
  # one card of every suit at one rank
  match suits:
    case Nil{}:
      Nil{}
    case s <> ss:
      Card{s, r} <> MS.rank_suits(r, ss)

def MS.fresh_deck(+ranks: +List<Rank>, +suits: +List<Suit>) -> +List<Card>:
  # the pre-shuffle deck: AC AD AH AS 2C 2D 2H 2S ... KC KD KH KS
  match ranks:
    case Nil{}:
      Nil{}
    case r <> rs:
      List.append(&2, Card, MS.rank_suits(r, suits), MS.fresh_deck(rs, suits))

def MS.step(left: Nat, +n: U32, state: U32, +xs: +List<Card>, out: +List<Card>) -> +List<Card>:
  # one round of the shuffle: deal the card at j = rand % n, and
  # move the card at n-1 into slot j; out gathers the dealt cards.
  # n is left as a number, so it can be read more than once.
  match left:
    case 0n:
      List.reverse(&2, Card, out)
    case 1n+p:
      +state2 = MS.next(state)
      r = U32.shrn(state2, 16n)
      +j = U32.mod(r, n)
      picked = Deck.at(xs, U32.to_nat(j), Card{Spades{}, Ace{}})
      tail = Deck.at(xs, U32.to_nat(U32.sub(n, 1)), Card{Spades{}, Ace{}})
      MS.step(p, U32.sub(n, 1), state2, List.set(&2, Card, xs, U32.to_nat(j), tail), picked <> out)

def MS.deck(game: U32) -> +List<Card>:
  # the 52 cards of a game number, in deal order
  MS.step(52n, 52, game, MS.fresh_deck(Rank.all(), MS.suits()), Nil{})

def Board.deal_ms(game: U32) -> Board:
  # the classic Microsoft deal by game number
  Board.deal(MS.deck(game))


# --- The rules, checked ----------------------------------------

def Board.move_ok(b: Board, m: Move) -> Maybe<&2, Unit>:
  # Some{Unit{}} when m is a legal move on b, None when a rule
  # fails. This function is the rules of freecell.
  match b m:
    case Board{cascades, cells, _} CascadeToCell{col, cell}:
      # the cascade must have a top card; the cell must exist and be free
      do Maybe<&2, Unit>:
        c : Card <- Piles.top_of(Piles.get(cascades, col))
        free : Unit <- check(Cells.is_free(cells, cell))
        return Unit{}
    case Board{+cascades, _, _} CascadeToCascade{+col, +col2}:
      # not a cascade onto itself; the source must have a top card,
      # and the target must accept it: empty, or one rank higher of
      # the opposite color
      do Maybe<&2, Unit>:
        ne : Unit <- check(U32.is_ne(col, col2))
        c : Card <- Piles.top_of(Piles.get(cascades, col))
        ok : Unit <- check(Piles.accepts(Piles.get(cascades, col2), c))
        return Unit{}
    case Board{cascades, _, founds} CascadeToFoundation{col}:
      # the foundation of the top card's suit must want exactly it
      do Maybe<&2, Unit>:
        c : Card <- Piles.top_of(Piles.get(cascades, col))
        ok : Unit <- check(Founds.takes(founds, c))
        return Unit{}
    case Board{cascades, cells, _} CellToCascade{cell, col}:
      # the cell must hold a card, and the cascade must accept it
      do Maybe<&2, Unit>:
        c : Card <- Cells.card(cells, cell)
        ok : Unit <- check(Piles.accepts(Piles.get(cascades, col), c))
        return Unit{}
    case Board{_, cells, founds} CellToFoundation{cell}:
      # the cell must hold a card its foundation wants next
      do Maybe<&2, Unit>:
        c : Card <- Cells.card(cells, cell)
        ok : Unit <- check(Founds.takes(founds, c))
        return Unit{}
    case Board{cascades, _, founds} FoundationToCascade{found, col}:
      # the pull: the foundation must hold its top card, and the
      # cascade must take it — empty, or one rank higher of the
      # opposite color, exactly as any other landing
      do Maybe<&2, Unit>:
        c : Card <- Founds.top_card(founds, found)
        ok : Unit <- check(Piles.accepts(Piles.get(cascades, col), c))
        return Unit{}

def Board.can_move(b: Board, m: Move) -> Bool:
  # is m a legal move on b?
  Maybe.is_some(&2, Unit, Board.move_ok(b, m))

# --- The rules, forced -----------------------------------------

def Board.force(b: Board, m: Move) -> Board:
  # perform m without checking it. Assumes Board.can_move(b, m);
  # on a move no rule could ever allow (an empty source, a missing
  # cascade) the board comes back unchanged.
  match b m:
    case Board{+cascades, cells, founds} CascadeToCell{+col, cell}:
      Board{Piles.pop_top(cascades, col), Cells.put_card(Piles.top_of(Piles.get(cascades, col)), cells, cell), founds}
    case Board{+cascades, cells, founds} CascadeToCascade{+col, col2}:
      Board{Piles.put_top(Piles.top_of(Piles.get(cascades, col)), Piles.pop_top(cascades, col), col2), cells, founds}
    case Board{+cascades, cells, founds} CascadeToFoundation{+col}:
      Board{Piles.pop_top(cascades, col), cells, Founds.inc_card(Piles.top_of(Piles.get(cascades, col)), founds)}
    case Board{cascades, +cells, founds} CellToCascade{+cell, +col}:
      Board{Piles.put_top(Cells.card(cells, cell), cascades, col), Cells.clear(cells, cell), founds}
    case Board{cascades, +cells, founds} CellToFoundation{+cell}:
      Board{cascades, Cells.clear(cells, cell), Founds.inc_card(Cells.card(cells, cell), founds)}
    case Board{cascades, cells, +founds} FoundationToCascade{+found, col}:
      Board{Piles.put_top(Founds.top_card(founds, found), cascades, col), cells, Founds.dec(founds, found)}

def Board.apply.go(ok: Bool, b: Board, m: Move) -> Maybe<&2, Board>:
  match ok:
    case True{}:
      Some{Board.force(b, m)}
    case False{}:
      None{}

def Board.apply(+b: Board, +m: Move) -> Maybe<&2, Board>:
  # the authoritative transition: the next board iff m is legal
  Board.apply.go(Board.can_move(b, m), b, m)

# --- Winning and counting --------------------------------------

def Board.is_won(b: Board) -> Bool:
  # every foundation complete: 13 cards apiece
  match b:
    case Board{_, _, founds}:
      List.all(~&2, ~U32, ~(c => U32.is_eq(c, 13)), founds)

def Board.card_count(b: Board) -> U32:
  # every card on the board: cascades, cells and foundations
  match b:
    case Board{cascades, cells, founds}:
      p c f = Piles.card_count(cascades) Cells.occupied(cells) Founds.total(founds)
      ((p + c : U32) + f : U32)

def Board.is_eq(a: Board, b: Board) -> Bool:
  # the same board: cascades, cells and foundations
  match a b:
    case Board{cascades, cells, founds} Board{cascades2, cells2, founds2}:
      Piles.is_eq(cascades, cascades2) && Cells.is_eq(cells, cells2) && Founds.is_eq(founds, founds2)

# --- Text, for debugging and the terminal game -----------------

def Pile.show(p: +List<Card>) -> String:
  List.show(~&2, ~Card, ~Card.show, p)

def Piles.show_lines(piles: +List<+List<Card>>) -> String:
  # one line per cascade
  match piles:
    case Nil{}:
      ""
    case p <> ps:
      "  " ++ Pile.show(p) ++ "\n" ++ Piles.show_lines(ps)

def Cell.show(m: +Maybe<Card>) -> String:
  match m:
    case None{}:
      "--"
    case Some{c}:
      Card.show(c)

def Cells.show(cells: +List<+Maybe<Card>>) -> String:
  List.show(~&2, ~+Maybe<Card>, ~Cell.show, cells)

def Founds.show(founds: +List<U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, founds)

def Board.show(b: Board) -> String:
  match b:
    case Board{cascades, cells, founds}:
      head = "cells: " ++ Cells.show(cells) ++ "  founds: " ++ Founds.show(founds) ++ "\ncascades:\n"
      head ++ Piles.show_lines(cascades)

def Move.show(m: Move) -> String:
  match m:
    case CascadeToCell{+col, +cell}:
      "cascade " ++ U32.show(col) ++ " to cell " ++ U32.show(cell)
    case CascadeToCascade{+col, +col2}:
      "cascade " ++ U32.show(col) ++ " to cascade " ++ U32.show(col2)
    case CascadeToFoundation{col}:
      "cascade " ++ U32.show(col) ++ " to foundation"
    case CellToCascade{+cell, +col}:
      "cell " ++ U32.show(cell) ++ " to cascade " ++ U32.show(col)
    case CellToFoundation{cell}:
      "cell " ++ U32.show(cell) ++ " to foundation"
    case FoundationToCascade{+found, +col}:
      "foundation " ++ U32.show(found) ++ " to cascade " ++ U32.show(col)

# --- A demo -----------------------------------------------------

def Demo.piles() -> +List<+List<Card>>:
  # two one-card cascades, six empty ones
  +e = {Nil{} : +List<Card>}
  [Card{Hearts{}, King{}} <> e, Card{Spades{}, Queen{}} <> e, e, e, e, e, e, e]

def Demo.cells() -> +List<+Maybe<Card>>:
  # the ace of clubs waits in cell 0
  [Some{Card{Clubs{}, Ace{}}}, None{}, None{}, None{}]

def Demo.founds() -> +List<U32>:
  [0, 0, 0, 0]

def Demo.board() -> Board:
  # a small board that exercises every rule
  Board{Demo.piles(), Demo.cells(), Demo.founds()}

def Demo.report.go(got: Maybe<&2, Board>, m: Move) -> String:
  match got:
    case Some{b2}:
      Move.show(m) ++ ": legal (the board still holds " ++ U32.show(Board.card_count(b2)) ++ " cards)"
    case None{}:
      Move.show(m) ++ ": illegal"

def Demo.report(b: Board, +m: Move) -> String:
  Demo.report.go(Board.apply(b, m), m)

def Demo.after(got: Maybe<&2, Board>) -> String:
  match got:
    case Some{b2}:
      "after the queen of spades moves onto the king of hearts:\n" ++ Board.show(b2)
    case None{}:
      "the move was illegal"

def Demo.run() -> String:
  +b = Demo.board()
  head = "a small board:\n" ++ Board.show(b) ++ "\n"
  r1 = Demo.report(b, CascadeToCascade{1, 0}) ++ "\n"
  r2 = Demo.report(b, CascadeToFoundation{1}) ++ "\n"
  r3 = Demo.report(b, CellToFoundation{0}) ++ "\n"
  r4 = Demo.report(b, CascadeToCell{0, 0}) ++ "\n"
  r5 = Demo.report(b, CascadeToCell{0, 1}) ++ "\n"
  after = Demo.after(Board.apply(b, CascadeToCascade{1, 0})) ++ "\n\n"
  d = Board.deal(Deck.new())
  foot = "a full deal of a natural deck:\n" ++ Board.show(d)
  head ++ r1 ++ r2 ++ r3 ++ r4 ++ r5 ++ after ++ foot

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Demo.run())
