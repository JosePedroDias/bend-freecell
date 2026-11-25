import Base
import ./LAWS.bend as Laws

# ===================================================================
# The proofs of the laws in LAWS.bend.
# ===================================================================
# Each seed law is a closed computation: both sides normalize to
# the same term, so reflexivity ({==}) proves it.

def Laws.deal_holds_all_cards():
  {==}

def Laws.empty_board_holds_no_cards():
  {==}

def Laws.fresh_game_is_not_won():
  {==}

def Laws.ms_game_1_first_row():
  {==}

def Laws.ms_game_1_whole_deal():
  {==}

def Laws.ms_deal_holds_all_cards():
  {==}

def Laws.ms_deal_11982_holds_all_cards():
  {==}

def Laws.server_governs_its_games():
  {==}

def Laws.dim_names_the_buried_noise():
  {==}
