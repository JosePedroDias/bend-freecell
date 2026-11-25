import Base
import ./freecell.bend as F
import ./plays.bend as P

# ===================================================================
# Terminal freecell: deal a Microsoft game, render it as text, read
# moves from stdin, and play by the rules of freecell.bend.
# ===================================================================
#   bend terminal-game.bend            # game 1
#   bend terminal-game.bend 11982      # the famously hard deal
#
# Moves are two words, <from> <to>: 1-8 a cascade, a-d a cell, h the
# foundations. A run is a count on the source: '1:2 3' carries two
# cards of column 1 onto column 3, expanded by the shared plays
# module into single moves the rules check. As a source, e-h names
# a foundation and pulls its top card back down: 'e 3'. Plus u
# (undo), r (redo), s (safe home moves), d (deal afresh), h (help)
# and q (quit).
#
# Bend has no read_line effect: the input is a File on /dev/stdin.
# That handle is linear, so it travels inside the State below, and
# every value that must be inspected goes to a helper matching its
# parameter: a local binder cannot be a match scrutinee. The only
# recursive def is Game.loop, spending one Nat of fuel per round.

# --- The game number --------------------------------------------

def Args.explicit(args: List<String>) -> Maybe<&2, U32>:
  # the game number asked for on the command line, if any
  match args:
    case Con{_, Con{a, _}}:
      U32.read(a)
    case _:
      None{}

def Args.session(+game: U32) -> U32 & F.Board:
  # a game number with its deal
  (game, F.Board.deal_ms(game))

# --- Commands ----------------------------------------------------

# one end of a move, as typed
type Place is Data:
  Col{idx: U32}
  CellP{idx: U32}
  FoundP{idx: U32}
  Home{}
  BadP{}

# a run grab, as typed: "1:2" — column 1, two cards
type Grab is Data:
  Grab{col: U32, count: U32}

# a whole command line, parsed
type Cmd is Data:
  Play{move: F.Move}
  Run{col: U32, count: U32, target: U32}
  Undo{}
  Redo{}
  Safe{}
  Deal{}
  Help{}
  Quit{}
  Skip{}
  Oops{msg: String}

# one round's whole world: the input handle is linear, so it
# travels with the game instead of being copied
type State is Type:
  State{board: F.Board, past: List<F.Board>, future: List<F.Board>, input: File}

def Parse.char_place(c: Char) -> Place:
  # a target: a column 1-8, a cell a-d, or the foundations h or f
  match c:
    case '1':
      Col{0}
    case '2':
      Col{1}
    case '3':
      Col{2}
    case '4':
      Col{3}
    case '5':
      Col{4}
    case '6':
      Col{5}
    case '7':
      Col{6}
    case '8':
      Col{7}
    case 'a':
      CellP{0}
    case 'b':
      CellP{1}
    case 'c':
      CellP{2}
    case 'd':
      CellP{3}
    case 'A':
      CellP{0}
    case 'B':
      CellP{1}
    case 'C':
      CellP{2}
    case 'D':
      CellP{3}
    case 'h':
      Home{}
    case 'H':
      Home{}
    case 'f':
      Home{}
    case 'F':
      Home{}
    case _:
      BadP{}

def Parse.char_src(c: Char) -> Place:
  # a source: a column 1-8, a cell a-d, or a foundation e-h — the
  # foundations are a home, not a trap, so their top card can be
  # pulled back down
  match c:
    case '1':
      Col{0}
    case '2':
      Col{1}
    case '3':
      Col{2}
    case '4':
      Col{3}
    case '5':
      Col{4}
    case '6':
      Col{5}
    case '7':
      Col{6}
    case '8':
      Col{7}
    case 'a':
      CellP{0}
    case 'b':
      CellP{1}
    case 'c':
      CellP{2}
    case 'd':
      CellP{3}
    case 'A':
      CellP{0}
    case 'B':
      CellP{1}
    case 'C':
      CellP{2}
    case 'D':
      CellP{3}
    case 'e':
      FoundP{0}
    case 'f':
      FoundP{1}
    case 'g':
      FoundP{2}
    case 'h':
      FoundP{3}
    case 'E':
      FoundP{0}
    case 'F':
      FoundP{1}
    case 'G':
      FoundP{2}
    case 'H':
      FoundP{3}
    case _:
      BadP{}

def Parse.place(tok: String) -> Place:
  # a one-letter place, or nothing
  match tok:
    case SNil{}:
      BadP{}
    case SCon{c, SNil{}}:
      Parse.char_place(c)
    case _:
      BadP{}

def Parse.src_place(tok: String) -> Place:
  # a one-letter source: a column, a cell, or a foundation
  match tok:
    case SNil{}:
      BadP{}
    case SCon{c, SNil{}}:
      Parse.char_src(c)
    case _:
      BadP{}

def Parse.one_cmd(t1: String) -> Cmd:
  # a single word: q quits, u undoes, r redoes, s sends safely, d
  # deals afresh, h or ? helps
  match t1:
    case SNil{}:
      Skip{}
    case SCon{'q', SNil{}}:
      Quit{}
    case SCon{'u', SNil{}}:
      Undo{}
    case SCon{'r', SNil{}}:
      Redo{}
    case SCon{'s', SNil{}}:
      Safe{}
    case SCon{'d', SNil{}}:
      Deal{}
    case SCon{'h', SNil{}}:
      Help{}
    case SCon{'?', SNil{}}:
      Help{}
    case _:
      Oops{"unknown command: two words make a move, 'h' for help"}

def Parse.grab_ok(col: Maybe<&2, U32>, count: Maybe<&2, U32>) -> Maybe<&2, Grab>:
  # a column and a count, both as typed: "1:2" is column 1, two cards
  match col count:
    case Some{+c} Some{+k}:
      Bool.pick(Maybe<&2, Grab>, U32.is_le(1, c) && U32.is_le(c, 8) && U32.is_le(1, k) && U32.is_le(k, 13),
        Some{Grab{U32.sub(c, 1), k}}, None{})
    case _ _:
      None{}

def Parse.grab_parts(parts: List<&2, String>) -> Maybe<&2, Grab>:
  # the two numbers of a grab, if they are there
  match parts:
    case Con{a, Con{b, Nil{}}}:
      Parse.grab_ok(U32.read(a), U32.read(b))
    case _:
      None{}

def Parse.grab(tok: String) -> Maybe<&2, Grab>:
  # "col:count" — a column, and how many of its cards to carry
  Parse.grab_parts(String.split(tok, ':'))

def Parse.run_target(target: Place) -> Maybe<&2, U32>:
  # a run lands on a column
  match target:
    case Col{idx}:
      Some{idx}
    case _:
      None{}

def Parse.run_of(got: Maybe<&2, U32>, +col: U32, +count: U32) -> Cmd:
  # the target column, if the run has one
  match got:
    case Some{t}:
      Run{col, count, t}
    case None{}:
      Oops{"a run lands only on a column: 1-8"}

def Parse.run_cmd(g: Grab, target: Place) -> Cmd:
  # "1:2 3" — carry two cards of column 1 onto column 3
  match g:
    case Grab{+col, +count}:
      Parse.run_of(Parse.run_target(target), col, count)

def Parse.move_cmd(src: Place, dst: Place) -> Cmd:
  # the six moves, and why any other pair makes no sense
  match src dst:
    case Col{a} CellP{b}:
      Play{F.CascadeToCell{a, b}}
    case Col{a} Col{b}:
      Play{F.CascadeToCascade{a, b}}
    case Col{a} Home{}:
      Play{F.CascadeToFoundation{a}}
    case CellP{b} Col{a}:
      Play{F.CellToCascade{b, a}}
    case CellP{b} Home{}:
      Play{F.CellToFoundation{b}}
    case FoundP{i} Col{a}:
      Play{F.FoundationToCascade{i, a}}
    case CellP{_} CellP{_}:
      Oops{"a card never moves from cell to cell"}
    case FoundP{_} _:
      Oops{"a home card lands only on a column: 1-8"}
    case _ FoundP{_}:
      Oops{"a card homes by its own suit: 'h', not a foundation"}
    case Home{} _:
      Oops{"pull from a foundation by its letter: e-h"}
    case _ BadP{}:
      Oops{"unknown target: 1-8, a-d or h"}
    case BadP{} _:
      Oops{"unknown source: 1-8, a-d or e-h"}

def Parse.pair_cmd(got: Maybe<&2, Grab>, t1: String, t2: String) -> Cmd:
  # two words: a run grab, or the two places of a single move
  match got:
    case Some{g}:
      Parse.run_cmd(g, Parse.place(t2))
    case None{}:
      Parse.move_cmd(Parse.src_place(t1), Parse.place(t2))

def Parse.tokens(toks: List<&2, String>) -> Cmd:
  # the words of a line
  match toks:
    case Con{+t1, Con{+t2, Nil{}}}:
      Parse.pair_cmd(Parse.grab(t1), t1, t2)
    case Con{t1, Nil{}}:
      Parse.one_cmd(t1)
    case Nil{}:
      Skip{}
    case _:
      Oops{"a move is two words, like '1 2'"}

def Parse.cmd(+line: String) -> Cmd:
  # a whole command line: "" (the end of the input) quits
  Bool.pick(Cmd, String.is_empty(line), Quit{},
    Parse.tokens(String.split(String.trim(line), ' ')))

# --- The board in text -------------------------------------------

def View.slot(m: Maybe<&2, F.Card>) -> String:
  # a card, or a blank of the same width
  match m:
    case None{}:
      "  "
    case Some{c}:
      F.Card.show(c)

def View.pad2(+n: U32) -> String:
  # a number right-aligned in two characters
  Bool.pick(String, U32.is_lt(n, 10), " " ++ U32.show(n), U32.show(n))

def View.suit_letters() -> +List<&2, String>:
  # the foundations in suit order, as letters — S H C D, the
  # colors alternating down the row
  ["S", "H", "C", "D"]

def View.cells_line(cells: +List<+Maybe<F.Card>>) -> String:
  # the four free cells
  match cells:
    case Nil{}:
      ""
    case c <> cs:
      "[" ++ F.Cell.show(c) ++ "] " ++ View.cells_line(cs)

def View.founds_line(founds: +List<U32>, letters: +List<&2, String>) -> String:
  # the four foundations: a suit letter and its depth
  match founds letters:
    case Nil{} _:
      ""
    case _ Nil{}:
      ""
    case n <> ns s <> ss:
      "[" ++ s ++ View.pad2(n) ++ "] " ++ View.founds_line(ns, ss)

def View.pile_row(+p: +List<F.Card>, +r: Nat) -> String:
  # the card at display row r of one column: the r-th card from the
  # bottom, the first dealt, and a blank past the top
  Bool.pick(String, Nat.is_lt(r, List.length(&2, F.Card, p)),
    View.slot(List.get(&2, F.Card, p, Nat.sub(Nat.sub(List.length(&2, F.Card, p), 1n), r))),
    "  ")

def View.row(piles: +List<+List<F.Card>>, +r: Nat) -> String:
  # display row r across the columns
  match piles:
    case Nil{}:
      ""
    case p <> ps:
      " " ++ View.pile_row(p, r) ++ " " ++ View.row(ps, r)

def View.rows(+piles: +List<+List<F.Card>>, k: Nat, +i: Nat) -> String:
  # display rows from row i up, deepest cards first; k rows remain
  match k:
    case 0n:
      ""
    case 1n+p:
      View.row(piles, i) ++ "\n" ++ View.rows(piles, p, 1n+i)

def View.height(piles: +List<+List<F.Card>>) -> Nat:
  # the longest column
  match piles:
    case Nil{}:
      0n
    case p <> ps:
      Nat.max(List.length(&2, F.Card, p), View.height(ps))

def View.show(b: F.Board) -> String:
  # the whole board, in text
  match b:
    case F.Board{+cascades, cells, founds}:
      h = View.height(cascades)
      head = "cells:  " ++ View.cells_line(cells) ++ " founds: " ++ View.founds_line(founds, View.suit_letters()) ++ "\n\n"
      head ++ " 1   2   3   4   5   6   7   8  \n" ++ View.rows(cascades, h, 0n)

# --- The game ----------------------------------------------------

def Game.help() -> String:
  # the commands
  l1 = {"moves are two words, <from> <to>:\n" : String}
  l2 = {"  1-8  a cascade column    a-d  a free cell    h  the foundation\n" : String}
  l3 = {"  e-h  a foundation, as the source of a pull back down\n" : String}
  l4 = {"  e.g. '1 2'  the top of column 1 onto column 2\n" : String}
  l5 = {"       '3 a'  park the top of column 3 in cell a\n" : String}
  l6 = {"       'b 4'  the card in cell b onto column 4\n" : String}
  l7 = {"       '2 h'  the top of column 2 to its foundation\n" : String}
  l8 = {"       'e 3'  the spade foundation's top card onto column 3\n" : String}
  l9 = {"  a run carries a column's climbing cards together:\n" : String}
  l10 = {"       '1:2 3'  two cards of column 1 onto column 3\n" : String}
  l11 = {"s: safe home moves    d: deal afresh\n" : String}
  l12 = {"u: undo    r: redo    q: quit    h: help\n" : String}
  l1 ++ l2 ++ l3 ++ l4 ++ l5 ++ l6 ++ l7 ++ l8 ++ l9 ++ l10 ++ l11 ++ l12

def Game.play(got: Maybe<&2, F.Board>, board: F.Board, past: List<F.Board>, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # a legal move goes onto the history, and the redo history dies;
  # an illegal one changes nothing
  match got:
    case Some{b2}:
      k(State{b2, board <> past, {Nil{} : List<F.Board>}, input})
    case None{}:
      do IO<Unit>:
        IO.print("illegal move\n")
        k(State{board, past, {Nil{} : List<F.Board>}, input})

def Game.undo(past: List<F.Board>, future: List<F.Board>, board: F.Board, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # go back one board, keeping it for the redo
  match past:
    case Nil{}:
      do IO<Unit>:
        IO.print("nothing to undo\n")
        k(State{board, past, future, input})
    case old <> rest:
      k(State{old, rest, board <> future, input})

def Game.redo(future: List<F.Board>, past: List<F.Board>, board: F.Board, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # go forward one board
  match future:
    case Nil{}:
      do IO<Unit>:
        IO.print("nothing to redo\n")
        k(State{board, past, future, input})
    case next <> rest:
      k(State{next, board <> past, rest, input})

def Game.safe_played(pair: F.Board & +List<F.Move>, past: List<F.Board>, future: List<F.Board>, board: F.Board, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # the plays' own answer: every safe home move and the board
  # after them
  (b2, ms) = pair
  match ms:
    case Nil{}:
      do IO<Unit>:
        IO.print("nothing is safe to send home\n")
        k(State{board, past, future, input})
    case _ <> _:
      do IO<Unit>:
        IO.print("sent " ++ U32.show(P.Play.counted(ms)) ++ " card(s) home\n")
        k(State{b2, board <> past, {Nil{} : List<F.Board>}, input})

def Game.safe(past: List<F.Board>, future: List<F.Board>, +board: F.Board, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # every card the foundations would take safely, in one word
  Game.safe_played(P.Play.safe(board), past, future, board, input, k)

def Game.deal(+game: U32, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # the same game, from its deal again
  do IO<Unit>:
    IO.print("game " ++ U32.show(game) ++ " dealt afresh\n")
    k(State{F.Board.deal_ms(game), {Nil{} : List<F.Board>}, {Nil{} : List<F.Board>}, input})

def Game.run_hauled(got: Maybe<&2, P.Haul>, past: List<F.Board>, future: List<F.Board>, board: F.Board, +count: U32, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # the plays expanded the run, or refused it
  match got:
    case None{}:
      do IO<Unit>:
        IO.print("the rules refuse this run\n")
        k(State{board, past, future, input})
    case Some{P.Haul{+b2, ms}}:
      do IO<Unit>:
        IO.print("carried " ++ U32.show(count) ++ " cards in " ++ U32.show(P.Play.counted(ms)) ++ " single moves\n")
        k(State{b2, board <> past, {Nil{} : List<F.Board>}, input})

def Game.run(past: List<F.Board>, future: List<F.Board>, +board: F.Board, +col: U32, +count: U32, +target: U32, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # a column's climbing run, carried by the plays every face
  # shares — one gesture, one undo
  Game.run_hauled(P.Play.supermove(board, col, U32.sub(count, 1), target), past, future, board, count, input, k)

def Game.handle(+game: U32, cmd: Cmd, input: File, +board: F.Board, past: List<F.Board>, future: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # one command, one answer, one next state
  match cmd:
    case Quit{}:
      do IO<Unit>:
        IO.print("bye\n")
    case Skip{}:
      k(State{board, past, future, input})
    case Help{}:
      do IO<Unit>:
        IO.print(Game.help())
        k(State{board, past, future, input})
    case Oops{msg}:
      do IO<Unit>:
        IO.print(msg ++ "\n")
        k(State{board, past, future, input})
    case Undo{}:
      Game.undo(past, future, board, input, k)
    case Redo{}:
      Game.redo(future, past, board, input, k)
    case Safe{}:
      Game.safe(past, future, board, input, k)
    case Deal{}:
      Game.deal(game, input, k)
    case Run{+col, +count, +target}:
      Game.run(past, future, board, col, count, target, input, k)
    case Play{move}:
      Game.play(F.Board.apply(board, move), board, past, input, k)

def Game.line(+game: U32, cmd: Cmd, input: File, +board: F.Board, past: List<F.Board>, future: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # parse the line, then act on it
  Game.handle(game, cmd, input, board, past, future, k)

def Game.read(+game: U32, fr: File & Result<&1, &1, U32 & String, String>, board: F.Board, past: List<F.Board>, future: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # the handle back beside the line it read, "" at the end
  (input, r) = fr
  Game.line(game, Parse.cmd(Result.default(&1, &1, U32 & String, String, r, "")), input, board, past, future, k)

def Game.won(+game: U32, won: Bool, board: F.Board, past: List<F.Board>, future: List<F.Board>, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # won games end before reading a command
  match won:
    case True{}:
      do IO<Unit>:
        IO.print("you won! every card is home\n")
    case False{}:
      do IO<Unit>:
        IO.write("> ")
        fr : File & Result<&1, &1, U32 & String, String> <- File.read_line(input, 64)
        Game.read(game, fr, board, past, future, k)

def Game.loop(fuel: Nat, +game: U32, st: State) -> IO(Unit):
  # show the board, read a command, act on it. One unit of fuel per
  # round; the closure below is the only recursive call, and every
  # one of its calls has less fuel than the round that made it
  match fuel:
    case 0n:
      do IO<Unit>:
        IO.print("session fuel spent — restart the program to keep playing\n")
    case 1n+p:
      match st:
        case State{+board, past, future, input}:
          do IO<Unit>:
            IO.print("game " ++ U32.show(game) ++ "\n" ++ View.show(board) ++ "\n")
            Game.won(game, F.Board.is_won(board), board, past, future, input, st2 => Game.loop(p, game, st2))

def Game.pick.go(bad: Bool, seed: U32, again: Unit -> IO(U32)) -> IO(U32):
  # 11982, the one unsolvable deal of the classic range, is re-drawn
  match bad:
    case True{}:
      again(Unit{})
    case False{}:
      do IO<U32>:
        return seed

def Game.pick.ok(+seed: U32, again: Unit -> IO(U32)) -> IO(U32):
  Game.pick.go(U32.is_eq(seed, 11982), seed, again)

def Game.pick(n: U32, again: Unit -> IO(U32)) -> IO(U32):
  # one draw of the generator, placed in the classic range 1..32000
  Game.pick.ok(U32.add(U32.mod(n, 32000), 1), again)

def Game.draw_seed(fuel: Nat) -> IO(U32):
  # a random game from the classic range 1..32000, where every deal
  # is solvable but 11982 — so draw, and re-draw a 11982. The
  # recursion is the closure below, one unit of fuel per draw
  match fuel:
    case 0n:
      do IO<U32>:
        return 1
    case 1n+p:
      do IO<U32>:
        n : U32 <- IO.try(U32, IO.random_u32())
        Game.pick(n, u => Game.draw_seed(p))

def Game.begin(session: U32 & F.Board, note: String) -> IO(Unit):
  # one session, given its game number, its deal and a first line
  (game, board) = session
  do IO<Unit>:
    IO.print(note)
    IO.print("freecell — type 'h' for help, 'q' to quit\n")
    input : File <- IO.try(File, File.open("/dev/stdin", "r"))
    Game.loop(100000n, game, State{board, {Nil{} : List<F.Board>}, {Nil{} : List<F.Board>}, input})

def Game.begin_seed(+n: U32) -> IO(Unit):
  # a randomly drawn game, its number said out loud
  Game.begin(Args.session(n), "random game " ++ U32.show(n) ++ "\n")

def Game.begin_arg(got: Maybe<&2, U32>) -> IO(Unit):
  # the game the arguments name, or a random solvable one
  match got:
    case Some{n}:
      Game.begin(Args.session(n), "")
    case None{}:
      do IO<Unit>:
        n : U32 <- Game.draw_seed(16n)
        Game.begin_seed(n)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Game.begin_arg(Args.explicit(args))
