#
# QuickCraps - plays 1000's of shooters at a table, and keeps stats on their rolls/turns.
#    Learn quickly how length of a shooters roll will translate to $$ win/loss.
#    Provide procs that determine how to bet and how to press on Pass Line, Place, Hardways, and Field
#    and compare strategies
#
class QuickCraps
  DEFAULT_NUM_PLAYERS = 6
  DEFAULT_NUM_SHOOTERS = DEFAULT_NUM_PLAYERS * 1000
  BET_UNIT=25
  TABLE_LIMIT=5000
  PLACE_DOUBLE_EVERY_OTHER_HIT = ->(bet_box, bet_hit_count, orig_amount, winnings) { bet_hit_count.even? ? orig_amount : 0 }

  attr_reader :players, :dice, :num_shooters, :shooter

  def initialize(num_players: DEFAULT_NUM_PLAYERS, num_shooters: DEFAULT_NUM_SHOOTERS)
    @players = create_players(num_players)
    @dice = Dice.new
    @next_player = 0
    @num_shooters = num_shooters
    @shooter = nil
  end

  def next_player_turn
    @shooter = players[calc_next_player]
    play_craps(shooter.new_player_turn(dice))
  end

  def self.run(**args)
    g = new(**args)
    g.run
    g.stats
  end

  def run
    num_shooters.times do
      next_player_turn
    end
  end

  def stats
    {
      players: players.map(&:stats),
      dice: dice.stats
    }
  end

  def inspect
    "#{players.length} players, #{dice.total_rolls} rolls of dice"
  end

  private

  def create_players(num_players)
    num_players.times.each_with_object([]) do |n, p|
      p << Player.new(name: "Player#{n+1}")
    end
  end

  def calc_next_player
    next_player_ind = @next_player
    if (@next_player += 1) == players.length
      @next_player = 0
    end
    next_player_ind
  end

  def play_craps(player_turn)
    Round.new(player_turn).play!
  end
end


class BetBox
  attr_reader :name, :wins_on, :loses_on, :pays, :for_every, :vig

  def initialize(name, wins_on, loses_on, pays, for_every, vig: 0, max_odds: nil)
    @name = name 
    @wins_on = wins_on
    @loses_on = loses_on
    @pays = pays
    @for_every = for_every
    @vig = vig
    @max_odds = max_odds
  end

  def evaluate(player_roll, bet_amount)
    if loses_on[player_roll]
      -bet_amount
    elsif wins_on[player_roll]
      winnings(bet_amount)
    else
      0
    end
  end

  def winnings(bet_amount)
    win_amt = (bet_amount / for_every ) * pays
    vig_amt = vig > 0 ? (amt * vig).floor : 0
    win_amt - vig_amt
  end

  def valid?(amount)
    return false if amount > QuickCraps::TABLE_LIMIT
    return false if amount < QuickCraps::BET_UNIT
    true
  end

  ROLL_ONE_OF = ->(*nums) { ->(roll) {Array[*nums].include?(roll.val)} }
  WINS_ON = ROLL_ONE_OF
  LOSES_ON = ROLL_ONE_OF
  SEVEN_OUT = LOSES_ON[7]
  LOSES_EASY = ->(number) { ->(roll) { roll.val == 7 || (roll.val == number && !roll.hard) } }
  WINS_ON_HARD = ->(number) { ->(roll) { roll.val == number && roll.hard } }

  PLACE = {
     4 => new(:place_4,  WINS_ON[4],  SEVEN_OUT, 2, 1, vig: 0.05),
     5 => new(:place_5,  WINS_ON[5],  SEVEN_OUT, 7, 5),
     6 => new(:place_6,  WINS_ON[6],  SEVEN_OUT, 7, 6),
     8 => new(:place_8,  WINS_ON[8],  SEVEN_OUT, 7, 6),
     9 => new(:place_9,  WINS_ON[9],  SEVEN_OUT, 7, 5),
    10 => new(:place_10, WINS_ON[10], SEVEN_OUT, 2, 1, vig: 0.05),
  }
  PASS_LINE = new(:pass_line, WINS_ON[[7,11]], LOSES_ON[2,3,12], 1, 1)
  PASS_POINT = {
     4 => new(:pass_4,  WINS_ON[4],  SEVEN_OUT, 1, 1),
     5 => new(:pass_5,  WINS_ON[5],  SEVEN_OUT, 1, 1),
     6 => new(:pass_6,  WINS_ON[6],  SEVEN_OUT, 1, 1),
     8 => new(:pass_8,  WINS_ON[8],  SEVEN_OUT, 1, 1),
     9 => new(:pass_9,  WINS_ON[9],  SEVEN_OUT, 1, 1),
    10 => new(:pass_10, WINS_ON[10], SEVEN_OUT, 1, 1)
  }
  PASS_ODDS = {
     4 => new(:pass_odds_4,  WINS_ON[4],  SEVEN_OUT, 2, 1, max_odds: 3),
     5 => new(:pass_odds_5,  WINS_ON[5],  SEVEN_OUT, 3, 2, max_odds: 4),
     6 => new(:pass_odds_6,  WINS_ON[6],  SEVEN_OUT, 6, 5, max_odds: 5),
     8 => new(:pass_odds_8,  WINS_ON[8],  SEVEN_OUT, 6, 5, max_odds: 5),
     9 => new(:pass_odds_9,  WINS_ON[9],  SEVEN_OUT, 3, 2, max_odds: 4),
    10 => new(:pass_odds_10, WINS_ON[10], SEVEN_OUT, 2, 1, max_odds: 3)
  }
  HARDWAYS = {
     4 => new(:hard_4,  WINS_ON_HARD[4],  LOSES_EASY[4], 7, 1),
     6 => new(:hard_6,  WINS_ON_HARD[6],  LOSES_EASY[6], 7, 1),
     8 => new(:hard_8,  WINS_ON_HARD[8],  LOSES_EASY[8], 9, 1),
    10 => new(:hard_10, WINS_ON_HARD[10], LOSES_EASY[10], 9, 1)
  }

  def to_s
    name.to_s
  end

  def inspect
    to_s
  end
end


class Bet
  attr_reader :player_turn, :bet_box, :amount, :rail, :press_strategy, :hit_count

  def initialize(player_turn, bet_box, amount, press_strategy: nil)
    @player_turn = player_turn
    @bet_box = bet_box
    @hit_count = 0
    @press_strategy = press_strategy

    # the amount continues to accumulate presses on top of the original bet
    @amount = amount

    # the rail reflects what the player has invested in this bet in the current
    # PlayerTurn,  And if positive, what profit he's secured if and when the bet should
    # lose.  If a player can take down the bet, the rail will increase as the @amount decreases.
    @rail = -amount
    validate!
  end

  def evaluate(player_roll)
    adjustment = bet_box.evaluate(player_roll, amount)

    if adjustment > 0
      @hit_count += 1
      press_amount = press_strategy ? press_strategy[bet_box, hit_count, amount, adjustment] : 0

      if (press_amount < 0)
        # press_strategy wants us to remove money from the current bet amount
        take_down(press_amount)
      else
        press_bet(adjustment, press_amount)
      end
    else
      # adjustment is 0 (bet stays the same), or -@amount (bet loses)
      @amount += adjustment
    end
  end

  def press_bet(adjustment, press_amount)
    @amount += press_amount
    @rail += (adjustment - press_amount)
  end

  def take_down(take_down_amount=@amount)
    @rail += take_down_amount
    @amount -= take_down_amount
  end

  def validate!
    raise "Invalid bet amount #{amount} for #{bet_box}" unless bet_box.valid?(amount)
  end
end


class TableState
  OFF = 0
  ON = 1

  attr_reader :point, :current_state

  def initialize
    set_off
  end

  def on?
    current_state == ON
  end

  def off?
    current_state == OFF
  end

  def set_off
    @current_state = OFF
    @point = nil
  end

  def set_on(point)
    @current_state = ON
    @point = point
  end
end


class Round
  WINNERS=[7,11]
  POINTS=[4,5,6,8,9,10]
  CRAPS=[2,3,12]

  attr_reader :player_turn, :table_state

  def initialize(player_turn)
    @player_turn = player_turn
    @table_state = TableState.new
  end

  def play!
    while player_roll; end
  end

  def player_roll
    player_turn.make_bets(table_state)

    roll = player_turn.roll

    keep_rolling = true

    if table_state.off?
      case roll.val
      when *WINNERS
        roll.winner
      when *POINTS
        table_state.set_on(roll.val)
        roll.point_established
      when *CRAPS
        roll.craps
      end
    elsif table_state.on?
      case roll.val
      when 7
        roll.seven_out
        table_state.set_off
        keep_rolling = false
      when *POINTS
        if roll.val == table_state.point
          roll.point_winner
          table_state.set_off
        else
          roll.place_winner
        end
      else # 2,3,11,12
        roll.horn_winner
      end
    end

    player_turn.pay_bets(roll)

    player_turn.keep_stats(roll)

    keep_rolling
  end
end


class PlayerRoll
  POINT_ESTABLISHED = :point
  FRONT_LINE_WINNER = :front_line_winner
  CRAPS             = :craps
  POINT_WINNER      = :point_winner
  PLACE_WINNER      = :place_winner
  HORN_WINNER       = :horn
  SEVEN_OUT         = :seven_out

  OUTCOME_SYMBOLS = {
    POINT_ESTABLISHED => "*",
    POINT_WINNER      => "!",
    FRONT_LINE_WINNER => "!",
    PLACE_WINNER      => "",
    CRAPS             => "x",
    HORN_WINNER       => "",
    SEVEN_OUT         => "x",
  }

  attr_reader :val
  attr_reader :outcome
  attr_reader :dice
  attr_reader :hard

  def initialize(dice)
    @dice = dice
    @val = nil
    @outcome = nil
    @hard = false
  end

  def roll
    dice.roll
    @hard = dice.hard?
    @val = dice.val
  end

  def point_established
    @outcome = POINT_ESTABLISHED
  end

  def seven_out
    @outcome = SEVEN_OUT
  end

  def winner
    @outcome = FRONT_LINE_WINNER
  end

  def craps
    @outcome = CRAPS
  end

  def point_winner
    @outcome = POINT_WINNER
  end

  def place_winner
    @outcome = PLACE_WINNER
  end

  def horn_winner
    @outcome = HORN_WINNER
  end

  def to_s
    format("%d%s%s", val, hard ? "h" : "", OUTCOME_SYMBOLS[outcome])
  end

  def inspect
    to_s
  end
end


class PlayerTurnStatsKeeper
  attr_reader :outcome_counts, :place_counts, :point_counts

  def initialize
    @outcome_counts = Hash.new(0)
    @place_counts   = Hash.new(0)
    @point_counts   = Hash.new(0)
  end

  def tally(player_roll)
    raise "no outcome yet" if player_roll.outcome.nil?

    outcome_counts[:total_rolls] += 1
    outcome_counts[player_roll.outcome] += 1

    case player_roll.outcome
    when PlayerRoll::PLACE_WINNER
      place_counts[player_roll.val] += 1
    when PlayerRoll::POINT_WINNER
      point_counts[player_roll.val] += 1
    end
  end

  def to_hash
    {
      outcomes:      outcome_counts,
      point_winners: point_counts,
      place_winners: place_counts
    }
  end
end


class PlayerTurn
  attr_reader :dice, :player, :rolls, :stats_keeper, :bets

  def initialize(player, dice)
    @dice = dice
    @player = player
    @rolls = []
    @bets = []
    @stats_keeper = PlayerTurnStatsKeeper.new
  end

  def roll
    PlayerRoll.new(dice).tap do |r|
      r.roll
      rolls << r
    end
  end

  def keep_stats(roll)
    stats_keeper.tally(roll)
  end

  def stats
    stats_keeper.to_hash
  end

  def make_bets(table_state)
    has_pass_line = has_bet?(BetBox::PASS_LINE)
    if table_state.off?
      bets << Bet.new(self, BetBox::PASS_LINE, QuickCraps::BET_UNIT) unless has_pass_line
    elsif has_pass_line
      remove_bet(BetBox::PASS_LINE)
      bets << Bet.new(self, BetBox::PASS_POINT[table_state.point], QuickCraps::BET_UNIT)
      bets << Bet.new(self, BetBox::PASS_ODDS[table_state.point], QuickCraps::BET_UNIT)
    end
  end

  def pay_bets(roll)
    bets.each do |bet|
      bet.evaluate(roll)
    end

    self
  end

  def remove_bet(bet_box)
    bet = find_bet(BetBox::PASS_LINE)
    bet.take_down
    bets.delete_if {|b| b == bet }
    self
  end

  def has_bet?(bet_box)
    !find_bet(bet_box).nil?
  end

  def find_bet(bet_box)
    bets.find {|b| b.bet_box == bet_box}
  end
end


class PlayerStats
  def initialize(player)
    @player = player
    @roll_lengths = Hash.new(0)
  end

  def to_hash
    {
      name:                   @player.name,
      roll_lengths:           all_roll_stats,
      longest_roll:           longest_roll_stats,
      avg_rolls_before_7_out: @player.turns.sum {|t| t.stats[:outcomes][:total_rolls]} / @player.turns.length,
    }
  end

  def longest_roll_stats
    longest_turn = @player.turns.max_by {|t| t.stats[:outcomes][:total_rolls]}
    {
      rolls: longest_turn.rolls.inspect,
      stats: longest_turn.stats
    }
  end

  def all_roll_stats
    @player.turns.each {|t| @roll_lengths[t.stats[:outcomes][:total_rolls]] += 1 }
    @roll_lengths.sort_by {|k,v| k}.to_h
  end
end


class Player
  attr_reader :name
  attr_reader :turns
  attr_reader :dice

  def initialize(name:)
    @name = name
    @turns = []
  end

  def new_player_turn(dice)
    PlayerTurn.new(self, dice).tap do |turn|
      @turns << turn
    end
  end

  def stats
    PlayerStats.new(self).to_hash
  end

  def inspect
    "#{name}: #{turns.length} turns"
  end
end

class Die
  NUM_FACES=6
  RANGE=1..NUM_FACES

  attr_reader :val

  def initialize(set_to=nil)
    if set_to
      set(set_to)
    else
      roll
    end
  end

  def set(val)
    raise "set must be in #{RANGE}" unless RANGE.include?(set)
    @val = set
  end

  def roll
    @val = rand(RANGE)
  end

  def inspect
    @val
  end
end


class Dice
  attr_reader :val, :total_rolls

  def initialize(num_dies=2)
    @dies = num_dies.times.each_with_object([]) {|n, o| o << Die.new}
    @freqs = Array.new(max_sum + 1)
    reset
  end

  def roll
    shake
    keep_stats
    val
  end

  def hard?
    [4,6,8,10].include?(val) && (@dies[0].val == @dies[1].val)
  end

  def reset
    @freqs.fill(0)
    @total_rolls = 0
    shake
  end

  def stats
    {
      total_rolls: @total_rolls,
      frequency: @freqs[2..-1].map.with_index(2) {|v, i| [i, v]}.to_h
    }
  end

  def to_s
    format("%2d %s", val, @dies.inspect)
  end

  def inspect
    to_s
  end

  private

  def shake
    @val = @dies.sum(&:roll)
    self
  end

  def max_sum
    Die::NUM_FACES * @dies.length
  end

  def keep_stats
    @total_rolls += 1
    @freqs[val] += 1
  end
end

def run(**args)
  QuickCraps.run(**args)
end
