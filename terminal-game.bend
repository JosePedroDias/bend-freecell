import Base
import ./freecell.bend as F

# ===================================================================
# Terminal freecell: deal a Microsoft game, render it as text, read
# moves from stdin, and play by the rules of freecell.bend.
# ===================================================================
#   bend terminal-game.bend            # game 1
#   bend terminal-game.bend 11982      # the famously hard deal
#
# Moves are two words, <from> <to>: 1-8 a cascade, a-d a cell, h the
# foundations; plus u (undo), h (help) and q (quit).
#
# Bend has no read_line effect: the input is a File on /dev/stdin.
# That handle is linear, so it travels inside the State below, and
# every value that must be inspected goes to a helper matching its
# parameter: a local binder cannot be a match scrutinee. The only
# recursive def is Game.loop, spending one Nat of fuel per round.

# --- The game number --------------------------------------------

def Args.number_of(got: Maybe<&2, U32>) -> U32:
  # the number a token reads as, or 1
  match got:
    case Some{n}:
      n
    case None{}:
      1

def Args.game(args: List<String>) -> U32:
  # the game number: the first argument after the program name
  match args:
    case Con{_, Con{a, _}}:
      Args.number_of(U32.read(a))
    case _:
      1

# --- Commands ----------------------------------------------------

# one end of a move, as typed
type Place is Data:
  Col{idx: U32}
  CellP{idx: U32}
  Home{}
  BadP{}

# a whole command line, parsed
type Cmd is Data:
  Play{move: F.Move}
  Undo{}
  Help{}
  Quit{}
  Skip{}
  Oops{msg: String}

# one round's whole world: the input handle is linear, so it
# travels with the game instead of being copied
type State is Type:
  State{board: F.Board, past: List<F.Board>, input: File}

def Parse.char_place(c: Char) -> Place:
  # a column 1-8, a cell a-d, or the foundations h or f
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

def Parse.place(tok: String) -> Place:
  # a one-letter place, or nothing
  match tok:
    case SNil{}:
      BadP{}
    case SCon{c, SNil{}}:
      Parse.char_place(c)
    case _:
      BadP{}

def Parse.one_cmd(t1: String) -> Cmd:
  # a single word: q quits, u undoes, h or ? helps
  match t1:
    case SNil{}:
      Skip{}
    case SCon{'q', SNil{}}:
      Quit{}
    case SCon{'u', SNil{}}:
      Undo{}
    case SCon{'h', SNil{}}:
      Help{}
    case SCon{'?', SNil{}}:
      Help{}
    case _:
      Oops{"unknown command: two words make a move, 'h' for help"}

def Parse.move_cmd(src: Place, dst: Place) -> Cmd:
  # the five moves, and why any other pair makes no sense
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
    case CellP{_} CellP{_}:
      Oops{"a card never moves from cell to cell"}
    case Home{} _:
      Oops{"the foundations keep their cards"}
    case _ BadP{}:
      Oops{"unknown target: 1-8, a-d or h"}
    case BadP{} _:
      Oops{"unknown source: 1-8, a-d or h"}

def Parse.tokens(toks: List<&2, String>) -> Cmd:
  # the words of a line
  match toks:
    case Con{t1, Con{t2, Nil{}}}:
      Parse.move_cmd(Parse.place(t1), Parse.place(t2))
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
  # the foundations in suit order, as letters
  ["S", "H", "D", "C"]

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
  l3 = {"  e.g. '1 2'  the top of column 1 onto column 2\n" : String}
  l4 = {"       '3 a'  park the top of column 3 in cell a\n" : String}
  l5 = {"       'b 4'  the card in cell b onto column 4\n" : String}
  l6 = {"       '2 h'  the top of column 2 to its foundation\n" : String}
  l7 = {"u: undo    q: quit    h: help\n" : String}
  l1 ++ l2 ++ l3 ++ l4 ++ l5 ++ l6 ++ l7

def Game.play(got: Maybe<&2, F.Board>, board: F.Board, past: List<F.Board>, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # a legal move goes onto the history; an illegal one changes nothing
  match got:
    case Some{b2}:
      k(State{b2, board <> past, input})
    case None{}:
      do IO<Unit>:
        IO.print("illegal move\n")
        k(State{board, past, input})

def Game.undo(past: List<F.Board>, board: F.Board, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # go back one board
  match past:
    case Nil{}:
      do IO<Unit>:
        IO.print("nothing to undo\n")
        k(State{board, past, input})
    case old <> rest:
      k(State{old, rest, input})

def Game.handle(cmd: Cmd, input: File, +board: F.Board, past: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # one command, one answer, one next state
  match cmd:
    case Quit{}:
      do IO<Unit>:
        IO.print("bye\n")
    case Skip{}:
      k(State{board, past, input})
    case Help{}:
      do IO<Unit>:
        IO.print(Game.help())
        k(State{board, past, input})
    case Oops{msg}:
      do IO<Unit>:
        IO.print(msg ++ "\n")
        k(State{board, past, input})
    case Undo{}:
      Game.undo(past, board, input, k)
    case Play{move}:
      Game.play(F.Board.apply(board, move), board, past, input, k)

def Game.line(input: File, line: String, board: F.Board, past: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # parse the line, then act on it
  Game.handle(Parse.cmd(line), input, board, past, k)

def Game.read(fr: File & Result<&1, &1, U32 & String, String>, board: F.Board, past: List<F.Board>, k: State -> IO(Unit)) -> IO(Unit):
  # the handle back beside the line it read, "" at the end
  (input, r) = fr
  Game.line(input, Result.default(&1, &1, U32 & String, String, r, ""), board, past, k)

def Game.won(won: Bool, board: F.Board, past: List<F.Board>, input: File, k: State -> IO(Unit)) -> IO(Unit):
  # won games end before reading a command
  match won:
    case True{}:
      do IO<Unit>:
        IO.print("you won! every card is home\n")
    case False{}:
      do IO<Unit>:
        IO.write("> ")
        fr : File & Result<&1, &1, U32 & String, String> <- File.read_line(input, 64)
        Game.read(fr, board, past, k)

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
        case State{+board, past, input}:
          do IO<Unit>:
            IO.print("game " ++ U32.show(game) ++ "\n" ++ View.show(board) ++ "\n")
            Game.won(F.Board.is_won(board), board, past, input, st2 => Game.loop(p, game, st2))

def Args.session(args: List<String>) -> U32 & F.Board:
  # the game number and its deal, from the command line
  +g = Args.game(args)
  (g, F.Board.deal_ms(g))

def Game.begin(session: U32 & F.Board) -> IO(Unit):
  # one session, given its game number and deal
  (game, board) = session
  do IO<Unit>:
    IO.print("freecell — type 'h' for help, 'q' to quit\n")
    input : File <- IO.try(File, File.open("/dev/stdin", "r"))
    Game.loop(100000n, game, State{board, Nil{}, input})

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    Game.begin(Args.session(args))
