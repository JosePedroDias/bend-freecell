import Base
import ./freecell.bend as F
import ./terminal-game.bend as T
import ./plays.bend as P

# ===================================================================
# The freecell server: an HTTP/1.1 authority over one or many abstract
# games, driven through the rules of freecell.bend.
# ===================================================================
#   bend server.bend            # listen on 127.0.0.1:8080
#   bend server.bend 9090        # another port
#
# The state lives here and nowhere else: no move is believed until
# the rules approve it. Each connection carries one request, and
# the answer closes it — HTTP/1.1, saying so with Connection: close.
# Bring a cookie — sid=alice — and the games you ask for are yours
# alone, kept under your name; the shared games answer anyone, and
# a session the server has not seen for an hour is wiped clean:
#
#   curl localhost:8080/1              # deal game 1, see it as JSON
#   curl localhost:8080/1 -d "1 a"     # a move, the terminal game's words
#   curl localhost:8080/1 -d "u"       # take it back
#   curl localhost:8080/1 -d "r"       # take it forward again
#   curl localhost:8080/1 -d "s"       # every safe home move
#   curl localhost:8080/1 -d "d"       # the same game, dealt afresh
#   curl localhost:8080/1 -d "1:2 3"   # a run, in single moves
#   curl localhost:8080/1 -d "1:2 a"   # a run, parked in the cells one apiece
#   curl localhost:8080/1 -d "e 3"     # the spade foundation's top, back down
#   curl localhost:8080/random         # a random solvable game
#   curl localhost:8080/games          # the open games
#   curl -b "sid=alice" localhost:8080/12 -d "1 a"   # alice's own game 12
#
# Answers are JSON — the whole board, or {"error": ...} with a 4xx.
# Commands are the terminal game's own words, so a whole winning
# line can be piped in move by move. The router below is pure: the
# sockets only carry it, and the laws can ask it directly.

# --- A session ----------------------------------------------------

# one taken step: the board before it, and how many single moves it
# cost — a supermove or a safe send counts its own
type Entry is Data:
  Entry{board: F.Board, n: U32}

# one game's whole truth: where it stands, every board it has stood
# at, every board it can stand at again, how many single moves
# brought it here, when the server last saw it, and the name of the
# session it belongs to — None, the shared game anyone may ask for
type Session is Data:
  Session{board: F.Board, past: +List<Entry>, future: +List<Entry>, moves: U32, seen: Nat, named: Maybe<&2, String>}

# the server's answer: an HTTP status and a JSON body
type Response is Data:
  Response{code: U32, why: String, body: String}

# one request, parsed to what it asks
type Req is Data:
  Root{}
  Games{}
  Random{}
  Show{game: U32}
  Act{game: U32, cmd: T.Cmd}
  NoRoute{}
  NoMethod{method: String}
  Oops{msg: String}

# one request, taken whole: what it asks, and the session it
# claims — None, the shared games
type Asked is Data:
  Asked{req: Req, sid: Maybe<&2, String>}

# --- The state as JSON --------------------------------------------

def Json.escape_char(c: Char) -> String:
  # the characters JSON quotes, quoted; every other stands as
  # itself — the server's text is ASCII
  match c:
    case '"':
      "\\\""
    case '\\':
      "\\\\"
    case '\n':
      "\\n"
    case '\r':
      "\\r"
    case '\t':
      "\\t"
    case _:
      String.from_list([c])

def Json.escape(cs: +List<Char>, +acc: String) -> String:
  # a string's characters, one by one
  match cs:
    case Nil{}:
      acc
    case c <> rest:
      Json.escape(rest, acc ++ Json.escape_char(c))

def Json.str(+s: String) -> String:
  # a JSON string, quotes and all
  "\"" ++ Json.escape(String.to_list(s), "") ++ "\""

def Json.num(+n: U32) -> String:
  # a JSON number
  U32.show(n)

def Json.bool(b: Bool) -> String:
  # a JSON boolean
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def Json.card(c: F.Card) -> String:
  # a card, as its two letters
  Json.str(F.Card.show(c))

def Json.cell(m: +Maybe<F.Card>) -> String:
  # a cell's card, or its emptiness
  match m:
    case None{}:
      "null"
    case Some{c}:
      Json.card(c)

def Json.cells(cells: +List<+Maybe<F.Card>>, +acc: String) -> String:
  # the cells, comma'd — the first without its comma
  match cells:
    case Nil{}:
      acc
    case +c <> +rest:
      Bool.pick(String, String.is_empty(acc),
        Json.cells(rest, Json.cell(c)),
        Json.cells(rest, acc ++ "," ++ Json.cell(c)))

def Json.cells_list(cells: +List<+Maybe<F.Card>>) -> String:
  # the four free cells, as a JSON array
  "[" ++ Json.cells(cells, "") ++ "]"

def Json.cards(cs: +List<F.Card>, +acc: String) -> String:
  # one column's cards, comma'd
  match cs:
    case Nil{}:
      acc
    case +c <> +rest:
      Bool.pick(String, String.is_empty(acc),
        Json.cards(rest, Json.card(c)),
        Json.cards(rest, acc ++ "," ++ Json.card(c)))

def Json.card_list(cs: +List<F.Card>) -> String:
  # one column, as a JSON array — index 0 is the bottom card
  "[" ++ Json.cards(cs, "") ++ "]"

def Json.piles(piles: +List<+List<F.Card>>, +acc: String) -> String:
  # the columns, comma'd
  match piles:
    case Nil{}:
      acc
    case +p <> +rest:
      Bool.pick(String, String.is_empty(acc),
        Json.piles(rest, Json.card_list(p)),
        Json.piles(rest, acc ++ "," ++ Json.card_list(p)))

def Json.pile_list(piles: +List<+List<F.Card>>) -> String:
  # the eight columns, as a JSON array of arrays
  "[" ++ Json.piles(piles, "") ++ "]"

def Json.nums(ns: +List<U32>, +acc: String) -> String:
  # the numbers, comma'd
  match ns:
    case Nil{}:
      acc
    case +n <> +rest:
      Bool.pick(String, String.is_empty(acc),
        Json.nums(rest, Json.num(n)),
        Json.nums(rest, acc ++ "," ++ Json.num(n)))

def Json.num_list(ns: +List<U32>) -> String:
  # a JSON array of numbers
  "[" ++ Json.nums(ns, "") ++ "]"

def Json.found(+letter: String, +n: U32) -> String:
  # one foundation, as a field
  Json.str(letter) ++ ":" ++ Json.num(n)

def Json.founds(founds: +List<U32>, +letters: +List<&2, String>, +acc: String) -> String:
  # the foundations, suit by suit: S, H, C, D — colors alternating
  match founds letters:
    case Nil{} _:
      acc
    case _ Nil{}:
      acc
    case +n <> +ns +s <> +ss:
      Bool.pick(String, String.is_empty(acc),
        Json.founds(ns, ss, Json.found(s, n)),
        Json.founds(ns, ss, acc ++ "," ++ Json.found(s, n)))

def Json.board_state(+game: U32, +moves: U32, board: F.Board) -> String:
  # a board as JSON: the game, the moves, the win, the cells, the
  # foundations, the columns
  match board:
    case F.Board{+cascades, +cells, +founds}:
      head = {"{\"game\": " ++ Json.num(game) ++ ", \"moves\": " ++ Json.num(moves) ++ ", \"won\": " ++ Json.bool(F.Board.is_won(board)) : String}
      cells_json = {", \"cells\": " ++ Json.cells_list(cells) : String}
      founds_json = {", \"foundations\": {" ++ Json.founds(founds, T.View.suit_letters(), "") ++ "}" : String}
      piles_json = {", \"cascades\": " ++ Json.pile_list(cascades) ++ "}" : String}
      head ++ cells_json ++ founds_json ++ piles_json

def Json.state(+game: U32, s: Session) -> String:
  # a session as one JSON object
  match s:
    case Session{+board, _, _, +moves, _, _}:
      Json.board_state(game, moves, board)

# --- The router: the house's whole authority ---------------------

def House.fresh(+game: U32, sid: Maybe<&2, String>, +now: Nat) -> Session:
  # a game's opening session: its deal, and no history yet, seen
  # just now, under the name it was asked for
  Session{F.Board.deal_ms(game), {Nil{} : +List<Entry>}, {Nil{} : +List<Entry>}, 0, now, sid}

def House.empty() -> Session:
  # the never-read default: the empty board can never be a live
  # session — the deck is somewhere, a law. Born stale and
  # unnamed, the sweep would take it at once
  Session{F.Board.empty(), {Nil{} : +List<Entry>}, {Nil{} : +List<Entry>}, 0, 0n, None{}}

def House.seen_of(s: Session) -> Nat:
  # when the server last saw the session
  match s:
    case Session{_, _, _, _, +seen, _}:
      seen

def House.named_of(s: Session) -> Maybe<&2, String>:
  # the session's name — None, the shared game
  match s:
    case Session{_, _, _, _, _, +named}:
      named

def House.touched(s: Session, +now: Nat) -> Session:
  # the same session, seen just now — its lease renewed
  match s:
    case Session{+board, +past, +future, +moves, _, +named}:
      Session{board, past, future, moves, now, named}

def House.key_of(sid: Maybe<&2, String>, +game: U32) -> String:
  # a game's key in the map: its number alone for the shared game,
  # the session's name in front of it when a client claims one
  match sid:
    case Some{+s}:
      s ++ "/" ++ U32.show(game)
    case None{}:
      U32.show(game)

def House.session_get(pair: +Map<Session> & Session) -> Session:
  # the map back, the session kept
  (games2, s) = pair
  s

def House.session_of(games: +Map<Session>, +key: String) -> Session:
  # the session behind a key, once has said it is there
  House.session_get(Map.get(Session, House.empty(), games, key))

def House.session_kept(+games: +Map<Session>, +key: String, +now: Nat) -> +Map<Session> & Session:
  # a session found: its lease renewed, its place kept
  (Map.set(&2, Session, games, key, House.touched(House.session_of(games, key), now)),
   House.touched(House.session_of(games, key), now))

def House.pick_session(present: Bool, +games: +Map<Session>, +key: String, +game: U32, +sid: Maybe<&2, String>, +now: Nat) -> +Map<Session> & Session:
  # the session found — its lease renewed — or the deal a first
  # reference deserves
  match present:
    case True{}:
      House.session_kept(games, key, now)
    case False{}:
      (Map.set(&2, Session, games, key, House.fresh(game, sid, now)), House.fresh(game, sid, now))

def House.session_pick(pair: +Map<Session> & Bool, +key: String, +game: U32, +sid: Maybe<&2, String>, +now: Nat) -> +Map<Session> & Session:
  # the map back beside its answer about the game
  (games2, present) = pair
  House.pick_session(present, games2, key, game, sid, now)

def House.session(games: +Map<Session>, +game: U32, +sid: Maybe<&2, String>, +now: Nat) -> +Map<Session> & Session:
  # a game's session under the name it was asked for, dealt on
  # first sight, its lease renewed on every sight
  House.session_pick(Map.has(&2, Session, games, House.key_of(sid, game)), House.key_of(sid, game), game, sid, now)

def House.board_of(s: Session) -> F.Board:
  match s:
    case Session{+board, _, _, _, _, _}:
      board

def House.moves_of(s: Session) -> U32:
  match s:
    case Session{_, _, _, +n, _, _}:
      n

def House.store(+games: +Map<Session>, +game: U32, +s2: Session) -> +Map<Session> & Session:
  # a session put back, under the name it carries
  (Map.set(&2, Session, games, House.key_of(House.named_of(s2), game), s2), s2)

def House.err(+games: +Map<Session>, +code: U32, +why: String, +msg: String) -> +Map<Session> & Response:
  # games unchanged, the refusal said as JSON
  (games, Response{code, why, "{\"error\": " ++ Json.str(msg) ++ "}"})

def House.stored(pair: +Map<Session> & Session, +game: U32) -> +Map<Session> & Response:
  # the stored session, shown
  (games2, s2) = pair
  (games2, Response{200, "OK", Json.state(game, s2)})

def House.stepped(s: Session, +b2: F.Board, +n: U32) -> Session:
  # a legal move: the new board, the old one remembered with its
  # cost, the future dead — the lease and the name carried over
  match s:
    case Session{+board, +past, _, +moves, +seen, +named}:
      Session{b2, Entry{board, n} <> past, {Nil{} : +List<Entry>}, (moves + n : U32), seen, named}

def House.applied_n(got: Maybe<&2, F.Board>, +n: U32, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # the rules' verdict on a move, with its cost
  match got:
    case Some{+b2}:
      House.stored(House.store(games, game, House.stepped(s, b2, n)), game)
    case None{}:
      House.err(games, 409, "Conflict", "the rules refuse this move")

def House.applied(got: Maybe<&2, F.Board>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # a single move: cost one
  House.applied_n(got, 1, games, game, s)

def House.play(+games: +Map<Session>, +game: U32, +s: Session, +move: F.Move) -> +Map<Session> & Response:
  # the rules are the only judge
  House.applied(F.Board.apply(House.board_of(s), move), games, game, s)

def House.went_back(past: +List<Entry>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # one board back, or the refusal to invent one
  match past:
    case Nil{}:
      House.err(games, 409, "Conflict", "nothing to undo")
    case Entry{+old, +n} <> rest:
      match s:
        case Session{+board, _, +future, +moves, +seen, +named}:
          House.stored(House.store(games, game,
            Session{old, rest, Entry{board, n} <> future, U32.sub(moves, n), seen, named}), game)

def House.undo(+games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  match s:
    case Session{_, +past, _, _, _, _}:
      House.went_back(past, games, game, s)

def House.went_forward(future: +List<Entry>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # one board forward again, or the refusal to invent one
  match future:
    case Nil{}:
      House.err(games, 409, "Conflict", "nothing to redo")
    case Entry{+next, +n} <> rest:
      match s:
        case Session{+board, +past, _, +moves, +seen, +named}:
          House.stored(House.store(games, game,
            Session{next, Entry{board, n} <> past, rest, (moves + n : U32), seen, named}), game)

def House.redo(+games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  match s:
    case Session{_, _, +future, _, _, _}:
      House.went_forward(future, games, game, s)

def House.applied_board(b2: F.Board, +n: U32, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # a board already reached, remembered as one step of n moves
  match s:
    case Session{+board, +past, _, +moves, +seen, +named}:
      House.stored(House.store(games, game,
        Session{b2, Entry{board, n} <> past, {Nil{} : +List<Entry>}, (moves + n : U32), seen, named}), game)

def House.safe_step(ms: +List<F.Move>, b2: F.Board, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # nothing is safe, or the whole send is one step
  match ms:
    case Nil{}:
      House.err(games, 409, "Conflict", "no card is safe to send home")
    case _ <> _:
      House.applied_board(b2, P.Play.counted(ms), games, game, s)

def House.safe_played(pair: F.Board & +List<F.Move>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # the plays' safe answer: the board after them, and the moves
  (b2, ms) = pair
  House.safe_step(ms, b2, games, game, s)

def House.safe(+games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # every safe home move the plays find, as one step
  match s:
    case Session{+board, _, _, _, _, _}:
      House.safe_played(P.Play.safe(board), games, game, s)

def House.deal_afresh(+games: +Map<Session>, +game: U32, +s: Session) -> +Map<Session> & Response:
  # the same game, from its deal again — the session's name and
  # lease carried over
  House.stored(House.store(games, game,
    House.fresh(game, House.named_of(s), House.seen_of(s))), game)

def House.run_hauled(got: Maybe<&2, P.Haul>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # the plays expanded the run, or refused it
  match got:
    case None{}:
      House.err(games, 409, "Conflict", "the rules refuse this run")
    case Some{P.Haul{+b2, ms}}:
      House.applied_board(b2, P.Play.counted(ms), games, game, s)

def House.run(+games: +Map<Session>, +game: U32, s: Session, +col: U32, +count: U32, +target: U32) -> +Map<Session> & Response:
  # a column's climbing run, carried by the plays every face
  # shares — one gesture, one step, one undo
  match s:
    case Session{+board, _, _, _, _, _}:
      House.run_hauled(P.Play.supermove(board, col, U32.sub(count, 1), target), games, game, s)

def House.park_hauled(got: Maybe<&2, P.Haul>, +games: +Map<Session>, +game: U32, s: Session) -> +Map<Session> & Response:
  # the plays parked the run, or refused it
  match got:
    case None{}:
      House.err(games, 409, "Conflict", "the free cells cannot hold this run")
    case Some{P.Haul{+b2, ms}}:
      House.applied_board(b2, P.Play.counted(ms), games, game, s)

def House.park(+games: +Map<Session>, +game: U32, s: Session, +col: U32, +count: U32, +cell: U32) -> +Map<Session> & Response:
  # a column's climbing run, parked in the free cells one card
  # apiece by the plays every face shares — one gesture, one step,
  # one undo
  match s:
    case Session{+board, _, _, _, _, _}:
      House.park_hauled(P.Play.cellsmove(board, col, U32.sub(count, 1), cell), games, game, s)

def House.command(+games: +Map<Session>, +game: U32, s: Session, cmd: T.Cmd) -> +Map<Session> & Response:
  # a command in the terminal game's words, judged by the same rules
  match cmd:
    case T.Play{+move}:
      House.play(games, game, s, move)
    case T.Run{+col, +count, +target}:
      House.run(games, game, s, col, count, target)
    case T.Park{+col, +count, +cell}:
      House.park(games, game, s, col, count, cell)
    case T.Undo{}:
      House.undo(games, game, s)
    case T.Redo{}:
      House.redo(games, game, s)
    case T.Safe{}:
      House.safe(games, game, s)
    case T.Deal{}:
      House.deal_afresh(games, game, s)
    case T.Help{}:
      (games, Response{200, "OK", "{\"help\": " ++ Json.str(T.Game.help()) ++ "}"})
    case T.Oops{+msg}:
      House.err(games, 400, "Bad Request", msg)
    case T.Quit{}:
      House.err(games, 400, "Bad Request", "q is for the terminal; here, closing the connection is quitting")
    case T.Skip{}:
      House.err(games, 400, "Bad Request", "post a command: '1 2' moves a card, '1:2 3' carries a run, '1:2 a' parks it in the cells, 'e 3' pulls a card back down, 's' sends safely, 'u' undoes, 'r' redoes, 'd' deals afresh, 'h' helps")

def House.with_session(pair: +Map<Session> & Session, +game: U32, +cmd: T.Cmd) -> +Map<Session> & Response:
  (games2, s) = pair
  House.command(games2, game, s, cmd)

def House.act(games: +Map<Session>, +game: U32, +cmd: T.Cmd, +sid: Maybe<&2, String>, +now: Nat) -> +Map<Session> & Response:
  # find the game, then take its command
  House.with_session(House.session(games, game, sid, now), game, cmd)

def House.shown(pair: +Map<Session> & Session, +game: U32) -> +Map<Session> & Response:
  (games2, s) = pair
  (games2, Response{200, "OK", Json.state(game, s)})

def House.show(games: +Map<Session>, +game: U32, +sid: Maybe<&2, String>, +now: Nat) -> +Map<Session> & Response:
  # the state, dealt on first sight
  House.shown(House.session(games, game, sid, now), game)

def House.id_glued(shared: Bool, +n: U32, cont: Unit -> List<&2, U32>) -> List<&2, U32>:
  # the number glued to the rest's reading, when the key is the
  # number spelled back — a session's key carries a name, and the
  # open games are nobody's private business
  match shared:
    case True{}:
      n <> cont(Unit{})
    case False{}:
      cont(Unit{})

def House.id_seen(got: Maybe<&2, U32>, +k: String, cont: Unit -> List<&2, U32>) -> List<&2, U32>:
  # the key read as the number, then spelled back for comparison
  match got:
    case Some{+n}:
      House.id_glued(String.eq(k, U32.show(n)), n, cont)
    case None{}:
      cont(Unit{})

def House.read_ids(keys: List<&2, String>) -> List<&2, U32>:
  # map keys, read back as the numbers they came from. The
  # recursion is the closure below, on the shorter tail
  match keys:
    case Nil{}:
      {Nil{} : List<&2, U32>}
    case +k <> ks:
      House.id_seen(U32.read(k), k, u => House.read_ids(ks))

def House.ids(games: +Map<Session>) -> List<&2, U32>:
  # the open games, least first
  List.sort(~U32, ~U32.is_le, House.read_ids(Map.keys(&2, Session, games)))

# --- The sweep ------------------------------------------------------

def House.lease() -> Nat:
  # how long a session may sit unseen before the sweep wipes it
  # clean: an hour of the clock's seconds — a number to change
  # when the house changes its mind
  3600n

def House.fresh_lease(+seen: Nat, +now: Nat) -> Bool:
  # seen less than a lease ago — the hour itself is stale
  Nat.is_lt(Nat.sub(now, seen), House.lease())

def House.pruned(fresh: Bool, +games2: +Map<Session>, +k: String) -> +Map<Session>:
  # the fresh map kept as it is, the stale one without its key
  match fresh:
    case True{}:
      games2
    case False{}:
      Map.del(&2, Session, games2, k)

def House.swept(got: +Map<Session> & Session, +k: String, +now: Nat, more: +Map<Session> -> +Map<Session>) -> +Map<Session>:
  # one session's lease, judged: fresh it stays, stale its key
  # goes from the map
  (games2, s) = got
  more(House.pruned(House.fresh_lease(House.seen_of(s), now), games2, k))

def House.sweep(keys: List<&2, String>, games: +Map<Session>, +now: Nat) -> +Map<Session>:
  # the housekeeping: every session past its lease is wiped, key
  # by key — the shared games too, for an hour unseen is an hour
  # too long, whatever name a game carries. The recursion is the
  # closure below, on the shorter tail
  match keys:
    case Nil{}:
      games
    case +k <> ks:
      House.swept(Map.get(Session, House.empty(), games, k), k, now,
        g2 => House.sweep(ks, g2, now))

def House.keep(+games: +Map<Session>, +now: Nat) -> +Map<Session>:
  # the sweep, from the outside — one call before a connection is
  # served, and the house stays its own size
  House.sweep(Map.keys(&2, Session, games), games, now)

def House.index() -> String:
  # what the root says: the three routes, and the session cookie
  # that turns the games private
  "{\"routes\": [\"GET /games — the open games\", \"GET /<game> — a game's state, dealt on first sight\", \"POST /<game> — a command in the terminal game's words, like '1 a'\", \"Cookie: sid=<your name> — play under your own session, wiped after an hour unseen\"]}"

def House.ask(+games: +Map<Session>, +now: Nat, sid: Maybe<&2, String>, req: Req) -> +Map<Session> & Response:
  # one request answered, the games grown, under the name the
  # request claims: the server's whole authority, in one pure
  # def — the sockets only carry it, and the laws can ask it
  # directly
  match req:
    case Root{}:
      (games, Response{200, "OK", House.index()})
    case Games{}:
      (games, Response{200, "OK", "{\"games\": " ++ Json.num_list(House.ids(games)) ++ "}"})
    case Random{}:
      House.err(games, 500, "Internal Server Error", "the socket should have drawn the game")
    case Show{+game}:
      House.show(games, game, sid, now)
    case Act{+game, +cmd}:
      House.act(games, game, cmd, sid, now)
    case NoRoute{}:
      House.err(games, 404, "Not Found", "the routes are GET /games, GET /<game> and POST /<game>")
    case NoMethod{+m}:
      House.err(games, 405, "Method Not Allowed", "only GET and POST are spoken")
    case Oops{+msg}:
      House.err(games, 400, "Bad Request", msg)

# --- The witness: the house, asked to govern ---------------------

def House.grown(pair: +Map<Session> & Response) -> +Map<Session>:
  # the games a request grew to
  (g, _) = pair
  g

def House.resp_code(r: Response) -> U32:
  match r:
    case Response{+code, _, _}:
      code

def House.code_is(r: Response, +code: U32) -> Bool:
  U32.is_eq(House.resp_code(r), code)

def House.board_at(games: +Map<Session>, +game: U32) -> F.Board:
  House.board_of(House.session_of(games, U32.show(game)))

def House.back_to_deal(board: F.Board, +deal: F.Board, +code: U32) -> Bool:
  U32.is_eq(code, 200) && F.Board.is_eq(board, deal)

def House.replay_refused(+took: Bool, +refused: Bool, a4: +Map<Session> & Response) -> Bool:
  # the undo, judged: it must return the very deal
  (g4, r4) = a4
  took && refused && House.back_to_deal(House.board_at(g4, 1), F.Board.deal_ms(1), House.resp_code(r4))

def House.move_taken(+took: Bool, a3: +Map<Session> & Response) -> Bool:
  # the same move again: the cell is taken now, so the rules
  # refuse — a refusal never touches the games
  (g3, r3) = a3
  House.replay_refused(took, House.code_is(r3, 409), House.ask(g3, 0n, None{}, Act{1, T.Undo{}}))

def House.after_move(a2: +Map<Session> & Response) -> Bool:
  # a legal move was offered to a fresh game 1: taken?
  (g2, r2) = a2
  House.move_taken(House.code_is(r2, 200), House.ask(g2, 0n, None{}, Act{1, T.Play{F.CascadeToCell{0, 0}}}))

def House.session_moves(games: +Map<Session>, sid: Maybe<&2, String>, +game: U32) -> U32:
  # the moves a named session stands at
  House.moves_of(House.session_of(games, House.key_of(sid, game)))

def House.alice_map() -> +Map<Session>:
  # alice's game 1, seen at the hundredth second, one move spent
  a1 = House.ask(Map.new(&2, Session), 100n, Some{"alice"}, Show{1})
  House.grown(House.ask(House.grown(a1), 100n, Some{"alice"}, Act{1, T.Play{F.CascadeToCell{0, 0}}}))

def House.there(pair: +Map<Session> & Bool) -> Bool:
  # the map back, the answer about the key kept
  (_, there) = pair
  there

def House.kept_after_sweep(+games: +Map<Session>, +key: String, +now: Nat) -> Bool:
  # the sweep's verdict on one key, asked after the fact
  House.there(Map.has(&2, Session, House.sweep(Map.keys(&2, Session, games), games, now), key))

def House.lease_claims(+games: +Map<Session>) -> Bool:
  # the sweep, judged: an hour less a heartbeat after sight keeps
  # the session, the hour itself wipes it
  House.kept_after_sweep(games, "alice/1", (99n + House.lease() : Nat))
    && Bool.not(House.kept_after_sweep(games, "alice/1", (100n + House.lease() : Nat)))

def House.session_claims() -> Bool:
  # the named sessions, judged: alice and bob may play the same
  # deal as two games, and the shared game sees neither
  +a2 : +Map<Session> = House.alice_map()
  b1 = House.grown(House.ask(Map.new(&2, Session), 100n, Some{"bob"}, Show{1}))
  sh = House.grown(House.ask(Map.new(&2, Session), 100n, None{}, Show{1}))
  U32.is_eq(House.session_moves(a2, Some{"alice"}, 1), 1)
    && U32.is_eq(House.session_moves(b1, Some{"bob"}, 1), 0)
    && U32.is_eq(House.session_moves(sh, None{}, 1), 0)
    && House.lease_claims(a2)

def House.self_check() -> Bool:
  # the server's witness to its own authority, and the laws':
  # asked for game 1 it deals it; asked to move column 1 to cell a
  # it moves it, the cell being empty; asked the same again it
  # refuses, the cell being taken; asked to undo it returns the
  # very deal; asked under two names, one deal is two games, the
  # shared one untouched; asked an hour later, a session is gone.
  # No sockets here — the pure router, alone
  m1 = House.grown(House.ask(Map.new(&2, Session), 0n, None{}, Show{1}))
  House.after_move(House.ask(m1, 0n, None{}, Act{1, T.Play{F.CascadeToCell{0, 0}}})) && House.session_claims()

# --- HTTP: the requests, the replies -------------------------------

def Http.num_or_zero(got: Maybe<&2, U32>) -> U32:
  # a number, or nothing said
  match got:
    case Some{+n}:
      n
    case None{}:
      0

def Http.len_or_zero(+digits: String) -> U32:
  Http.num_or_zero(U32.read(digits))

def Http.read_last(got: Maybe<&2, String>, rest: Unit -> U32) -> U32:
  # the digits after the colon
  match got:
    case Some{+digits}:
      Http.len_or_zero(String.trim(digits))
    case None{}:
      rest(Unit{})

def Http.header_hits(hit: Bool, +h: String, rest: Unit -> U32) -> U32:
  # the one header that names the body's length
  match hit:
    case True{}:
      Http.read_last(List.last(&2, String, String.split(h, ':')), rest)
    case False{}:
      rest(Unit{})

def Http.content_len(headers: List<&2, String>) -> U32:
  # what the client promised the body would be, if it said. The
  # recursion is the closure below, on the shorter tail
  match headers:
    case Nil{}:
      0
    case +h <> hs:
      Http.header_hits(String.starts_with(String.to_lower(h), "content-length:"), h, u => Http.content_len(hs))

def Http.cookie_named(is_sid: Bool, +val: String, more: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  # the pair judged: the sid's value claimed, or the walk goes on
  match is_sid:
    case True{}:
      Some{String.trim(val)}
    case False{}:
      more(Unit{})

def Http.cookie_pair(parts: List<&2, String>, more: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  # one pair: 'sid=alice' names the session, anything else is
  # the next pair's business
  match parts:
    case Con{+name, Con{+val, Nil{}}}:
      Http.cookie_named(String.eq(String.trim(name), "sid"), val, more)
    case _:
      more(Unit{})

def Http.cookie_sid(pairs: List<&2, String>) -> Maybe<&2, String>:
  # the sid pair among the cookie's pairs: 'a=1; sid=alice'. The
  # recursion is the closure below, on the shorter tail
  match pairs:
    case Nil{}:
      None{}
    case +p <> ps:
      Http.cookie_pair(String.split(String.trim(p), '='), u => Http.cookie_sid(ps))

def Http.cookie_last(got: Maybe<&2, String>) -> Maybe<&2, String>:
  # the value after the header's colon, walked for its sid pair —
  # or nothing, when the colon was the last character
  match got:
    case Some{+v}:
      Http.cookie_sid(String.split(String.trim(v), ';'))
    case None{}:
      None{}

def Http.cookie_hit(hit: Bool, +h: String, more: Unit -> Maybe<&2, String>) -> Maybe<&2, String>:
  # one header: the Cookie: header carries the claim
  match hit:
    case True{}:
      Http.cookie_last(List.last(&2, String, String.split(h, ':')))
    case False{}:
      more(Unit{})

def Http.cookie_of(headers: List<&2, String>) -> Maybe<&2, String>:
  # the session a client claims: the sid pair of its Cookie:
  # header, wherever it sits among the other pairs. No header,
  # no claim — the shared games are the client's. The recursion
  # is the closure below, on the shorter tail
  match headers:
    case Nil{}:
      None{}
    case +h <> hs:
      Http.cookie_hit(String.starts_with(String.to_lower(h), "cookie:"), h, u => Http.cookie_of(hs))

def Http.token_ok(ok: Bool, tok: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      Some{tok}
    case False{}:
      None{}

def Http.token(parts: List<&2, String>) -> Maybe<&2, String>:
  # "/tok" — the one word after the leading slash
  match parts:
    case Con{lead, Con{tok, Nil{}}}:
      Http.token_ok(String.is_empty(lead), tok)
    case _:
      None{}

def Http.token_of(path: String) -> Maybe<&2, String>:
  Http.token(String.split(path, '/'))

def Http.num_of(got: Maybe<&2, String>) -> Maybe<&2, U32>:
  match got:
    case None{}:
      None{}
    case Some{+tok}:
      U32.read(tok)

def Http.range_ok(ok: Bool, got: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      got
    case False{}:
      None{}

def Http.game_ok(got: Maybe<&2, U32>) -> Maybe<&2, U32>:
  # a deal of the classic range, 1..32000
  match got:
    case Some{+n}:
      Http.range_ok(U32.is_le(1, n) && U32.is_le(n, 32000), got)
    case None{}:
      None{}

def Http.game_of(path: String) -> Maybe<&2, U32>:
  Http.game_ok(Http.num_of(Http.token_of(path)))

def Http.get_game(got: Maybe<&2, U32>) -> Req:
  match got:
    case Some{+n}:
      Show{n}
    case None{}:
      NoRoute{}

def Http.get_root(is_root: Bool, +path: String) -> Req:
  match is_root:
    case True{}:
      Root{}
    case False{}:
      Http.get_game(Http.game_of(path))

def Http.get_root_or_random(is_root: Bool, +path: String) -> Req:
  # "/" names the routes; "/random" rolls the dice; anything else
  # names a game
  match is_root:
    case True{}:
      Root{}
    case False{}:
      Http.get_game(Http.game_of(path))

def Http.get_random(is_random: Bool, +path: String) -> Req:
  match is_random:
    case True{}:
      Random{}
    case False{}:
      Http.get_root_or_random(String.eq(path, "/"), path)

def Http.get_games(is_games: Bool, +path: String) -> Req:
  match is_games:
    case True{}:
      Games{}
    case False{}:
      Http.get_random(String.eq(path, "/random"), path)

def Http.get(+path: String) -> Req:
  Http.get_games(String.eq(path, "/games"), path)

def Http.post_game(got: Maybe<&2, U32>, +body: String) -> Req:
  # a command for a game, in the terminal game's words
  match got:
    case Some{+n}:
      Act{n, T.Parse.cmd(body)}
    case None{}:
      NoRoute{}

def Http.post(path: String, +body: String) -> Req:
  Http.post_game(Http.game_of(path), body)

def Http.post_or_405(is_post: Bool, +m: String, +path: String, +body: String) -> Req:
  match is_post:
    case True{}:
      Http.post(path, body)
    case False{}:
      NoMethod{m}

def Http.pick_method(is_get: Bool, +m: String, +path: String, +body: String) -> Req:
  match is_get:
    case True{}:
      Http.get(path)
    case False{}:
      Http.post_or_405(String.eq(m, "POST"), m, path, body)

def Http.ver_ok(ok: Bool, +m: String, +path: String, +body: String) -> Req:
  match ok:
    case False{}:
      Oops{"HTTP it is not, or its version is missing"}
    case True{}:
      Http.pick_method(String.eq(m, "GET"), m, path, body)

def Http.verb(+m: String, +path: String, +ver: String, +body: String) -> Req:
  Http.ver_ok(String.starts_with(ver, "HTTP/"), m, path, body)

def Http.line_route(parts: List<&2, String>, +body: String) -> Req:
  # METHOD /path HTTP/x.y — three words
  match parts:
    case Con{m, Con{path, Con{ver, Nil{}}}}:
      Http.verb(m, path, ver, body)
    case _:
      Oops{"a request line is 'METHOD /path HTTP/1.1'"}

def Http.route(+reqline: String, +body: String) -> Req:
  # the request line names a method and a path; the body carries
  # the command
  Http.line_route(String.split(String.trim(reqline), ' '), body)

def Http.request_full(+clen: U32, +sid: Maybe<&2, String>, +reqline: String, +body: List<&2, String>) -> Maybe<&2, Asked>:
  # the request is whole when the body holds what content-length
  # promised — ASCII bodies, so characters are bytes — and beside
  # it the session the request claims
  complete = {U32.is_le(clen, U32.from_nat(String.length(String.join(body, "\n")))) : Bool}
  Bool.pick(Maybe<&2, Asked>, complete, Some{Asked{Http.route(reqline, String.join(body, "\n")), sid}}, None{})

def Http.request(+reqline: String, +headers: List<&2, String>, +body: List<&2, String>) -> Maybe<&2, Asked>:
  # headers done; the body must now be as long as promised, and
  # the session read from among them
  Http.request_full(Http.content_len(headers), Http.cookie_of(headers), reqline, body)

def Http.blank_line(l: String) -> Bool:
  # the line that ends the headers: empty, or a bare carriage
  # return the split left behind. Body lines are never blanked —
  # a body of one space is a whole body
  match l:
    case SNil{}:
      True{}
    case SCon{'\r', SNil{}}:
      True{}
    case _:
      False{}

def Http.blank(blank: Bool, +reqline: String, hs: List<&2, String>, +headers: List<&2, String>, more: Unit -> Maybe<&2, Asked>) -> Maybe<&2, Asked>:
  # the blank line ends the headers; the body follows it
  match blank:
    case True{}:
      Http.request(reqline, headers, hs)
    case False{}:
      more(Unit{})

def Http.headed(+reqline: String, +rest: List<&2, String>, +headers: List<&2, String>) -> Maybe<&2, Asked>:
  # gather the header lines until the blank line; the body follows,
  # its lines untouched. The recursion is the closure below, on
  # the shorter tail
  match rest:
    case Nil{}:
      None{}
    case +h <> hs:
      Http.blank(Http.blank_line(h), reqline, hs, headers, u => Http.headed(reqline, hs, h <> headers))

def Http.lines(lines: List<&2, String>) -> Maybe<&2, Asked>:
  # the request line first, the headers after, the body last —
  # all exactly as they arrived
  match lines:
    case Nil{}:
      None{}
    case reqline <> rest:
      Http.headed(reqline, rest, {Nil{} : List<&2, String>})

def Http.parse(+acc: String) -> Maybe<&2, Asked>:
  # nothing until the whole request has arrived, then the request
  # and the session it claims
  Http.lines(String.split(acc, '\n'))

def Http.reply(resp: Response) -> String:
  # an answer in full: the status line, the headers, the JSON body
  match resp:
    case Response{+code, +why, +body}:
      head = {"HTTP/1.1 " ++ Json.num(code) ++ " " ++ why ++ "\r\n" : String}
      type_line = {"Content-Type: application/json\r\n" : String}
      len_line = {"Content-Length: " ++ Json.num(U32.from_nat(String.length(body))) ++ "\r\n" : String}
      head ++ type_line ++ len_line ++ "Connection: close\r\n\r\n" ++ body

# --- One connection ------------------------------------------------

def Talk.spent(w: Socket & String, +games: +Map<Session>) -> IO(+Map<Session>):
  # the fuel gone: whatever arrived, it never made a request
  (sock, _) = w
  do IO<+Map<Session>>:
    Socket.close(sock)
    return games

def Talk.sent(fr2: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, +g2: +Map<Session>) -> IO(+Map<Session>):
  # a send that cannot finish is dropped, not resumed — the answers
  # are small, and the connection closes either way
  (sock2, _) = fr2
  do IO<+Map<Session>>:
    Socket.close(sock2)
    return g2

def Talk.answer(pair: +Map<Session> & Response, sock: Socket) -> IO(+Map<Session>):
  # the games grown beside the reply they earned
  (g2, resp) = pair
  do IO<+Map<Session>>:
    fr2 : Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit> <- TCP.send(sock, Http.reply(resp))
    Talk.sent(fr2, g2)

def Talk.routed(req: Req, sid: Maybe<&2, String>, sock: Socket, +games: +Map<Session>, +now: Nat) -> IO(+Map<Session>):
  # /random draws its game here, where the IO lives; the router
  # stays pure, the dice roll in the socket's world, and whatever
  # session the request claimed goes with the question
  match req:
    case Random{}:
      do IO<+Map<Session>>:
        n : U32 <- T.Game.draw_seed(16n)
        Talk.answer(House.ask(games, now, sid, Show{n}), sock)
    case _:
      Talk.answer(House.ask(games, now, sid, req), sock)

def Talk.ended(got: Maybe<&2, Asked>, sock: Socket, +games: +Map<Session>, +now: Nat) -> IO(+Map<Session>):
  # the client said all it would say: answer it if it said a whole
  # request, and keep what the answer grew
  match got:
    case Some{Asked{+req, +sid}}:
      Talk.routed(req, sid, sock, games, now)
    case None{}:
      do IO<+Map<Session>>:
        Socket.close(sock)
        return games

def Talk.grown(got: Maybe<&2, Asked>, sock: Socket, +acc2: String, +games: +Map<Session>, +now: Nat, more: (Socket & String) -> IO(+Map<Session>)) -> IO(+Map<Session>):
  # after a read: a whole request is answered at once, a part
  # awaits the rest
  match got:
    case Some{Asked{+req, +sid}}:
      Talk.routed(req, sid, sock, games, now)
    case None{}:
      more((sock, acc2))

def Talk.data(data: Maybe<&1, String>, sock: Socket, +acc: String, +games: +Map<Session>, +now: Nat, more: (Socket & String) -> IO(+Map<Session>)) -> IO(+Map<Session>):
  # a chunk, or the end of the client's side
  match data:
    case Some{+chunk}:
      Talk.grown(Http.parse(acc ++ chunk), sock, acc ++ chunk, games, now, more)
    case None{}:
      Talk.ended(Http.parse(acc), sock, games, now)

def Talk.got(fr: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, +acc: String, +games: +Map<Session>, +now: Nat, more: (Socket & String) -> IO(+Map<Session>)) -> IO(+Map<Session>):
  # the socket back beside what arrived
  (sock2, r) = fr
  match r:
    case Done{data}:
      Talk.data(data, sock2, acc, games, now, more)
    case Fail{(code, msg)}:
      do IO<+Map<Session>>:
        IO.print_err("recv: " ++ msg ++ "\n")
        Socket.close(sock2)
        return games

def Talk.reading(w: Socket & String, +games: +Map<Session>, +now: Nat, more: (Socket & String) -> IO(+Map<Session>)) -> IO(+Map<Session>):
  # one read, and everything the socket has said so far
  (sock, acc) = w
  do IO<+Map<Session>>:
    fr : Socket & Result<&1, &1, U32 & String, Maybe<&1, String>> <- TCP.recv(sock, 4096)
    Talk.got(fr, acc, games, now, more)

def Talk.round(fuel: Nat, w: Socket & String, +games: +Map<Session>, +now: Nat) -> IO(+Map<Session>):
  # one connection's reads, a unit of fuel each: the socket and
  # everything it has said so far travel together, the games the
  # connection leaves come back out, and the clock the connection
  # was greeted by goes with them. The recursion is the closure
  # below — every call to it has less fuel
  match fuel:
    case 0n:
      Talk.spent(w, games)
    case 1n+p:
      Talk.reading(w, games, now, w2 => Talk.round(p, w2, games, now))

# --- The accept loop -----------------------------------------------

def Serve.opened(fr: Listener & Result<&1, &1, U32 & String, Socket>, +games: +Map<Session>, next: (Listener & +Map<Session>) -> IO(Unit)) -> IO(Unit):
  # a client at the door, or a failure to see one. The house is
  # swept first — no session sits unseen past its lease — then the
  # connection is served to its end, and the games it leaves come
  # back
  (l2, r) = fr
  match r:
    case Done{sock}:
      do IO<Unit>:
        +now : Nat <- IO.now()
        g2 : +Map<Session> <- Talk.round(64n, (sock, ""), House.keep(games, now), now)
        next((l2, g2))
    case Fail{(code, msg)}:
      do IO<Unit>:
        IO.print_err("accept: " ++ msg ++ "\n")
        next((l2, games))

def Serve.spent(w: Listener & +Map<Session>) -> IO(Unit):
  # the fuel gone: the door closes after 2^32 rounds
  (listener, _) = w
  do IO<Unit>:
    Listener.close(listener)
    IO.print_err("the server has answered its last round\n")

def Serve.round(w: Listener & +Map<Session>, next: (Listener & +Map<Session>) -> IO(Unit)) -> IO(Unit):
  # one connection sought
  (listener, games) = w
  do IO<Unit>:
    fr : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    Serve.opened(fr, games, next)

def Serve.serve(fuel: Nat, w: Listener & +Map<Session>) -> IO(Unit):
  # one connection a round, and 2^32 rounds is the runtime's own
  # idea of forever — its windows loop stops there too. The
  # recursion is the closure below
  match fuel:
    case 0n:
      Serve.spent(w)
    case 1n+p:
      Serve.round(w, w2 => Serve.serve(p, w2))

# --- The door -----------------------------------------------------

def Args.port_or(got: Maybe<&2, U32>) -> U32:
  # a port, or the default
  match got:
    case Some{+n}:
      n
    case None{}:
      8080

def Args.port(args: List<String>) -> U32:
  # the port asked for on the command line, or 8080
  match args:
    case Con{_, Con{a, _}}:
      Args.port_or(U32.read(a))
    case _:
      8080

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +port : U32 = Args.port(args)
    IO.print_err("freecell server — self check: " ++ Json.bool(House.self_check()) ++ "\n")
    IO.print_err("listening on http://127.0.0.1:" ++ Json.num(port) ++ " — try: curl localhost:" ++ Json.num(port) ++ "/1\n")
    l : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", port))
    Serve.serve(4294967295n, (l, Map.new(&2, Session)))
