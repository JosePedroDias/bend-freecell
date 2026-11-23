import Base
import ./freecell.bend as FreeCell

# ===================================================================
# The laws of freecell: the claims the game rules must answer to.
# ===================================================================
# Goal 1 seeds these; goal 2 grows them into the full rule book.

# A dealt board holds the whole deck: nothing is lost, duplicated or
# invented by the deal.
law deal_holds_all_cards:
  {FreeCell.Board.card_count(FreeCell.Board.deal(FreeCell.Deck.new())) == 52 : U32}

# An empty board holds no cards.
law empty_board_holds_no_cards:
  {FreeCell.Board.card_count(FreeCell.Board.empty()) == 0 : U32}

# A game that has not started is not won: every foundation is empty.
law fresh_game_is_not_won:
  {FreeCell.Board.is_won(FreeCell.Board.empty()) == False{} : Bool}

# The Microsoft deals: a game number picks the cards, as published.
# Game 1 opens with its famous first row.
law ms_game_1_first_row:
  {List.take(&2, FreeCell.Card, FreeCell.MS.deck(1), 8n) == [FreeCell.Card{FreeCell.Diamonds{}, FreeCell.Jack{}}, FreeCell.Card{FreeCell.Diamonds{}, FreeCell.Two{}}, FreeCell.Card{FreeCell.Hearts{}, FreeCell.Nine{}}, FreeCell.Card{FreeCell.Clubs{}, FreeCell.Jack{}}, FreeCell.Card{FreeCell.Diamonds{}, FreeCell.Five{}}, FreeCell.Card{FreeCell.Hearts{}, FreeCell.Seven{}}, FreeCell.Card{FreeCell.Clubs{}, FreeCell.Seven{}}, FreeCell.Card{FreeCell.Hearts{}, FreeCell.Five{}}] : +List<FreeCell.Card>}

law ms_deal_holds_all_cards:
  {FreeCell.Board.card_count(FreeCell.Board.deal_ms(1)) == 52 : U32}

law ms_deal_11982_holds_all_cards:
  {FreeCell.Board.card_count(FreeCell.Board.deal_ms(11982)) == 52 : U32}
