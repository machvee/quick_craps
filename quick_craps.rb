#
# QuickCraps - plays 1000's of shooters at a table, and keeps stats on their rolls/turns.
#    Learn quickly how length of a shooters roll will translate to $$ win/loss.
#    Provide procs that determine how to bet and how to press on Pass Line, Place, Hardways, and Field
#    and compare strategies
#
module QuickCraps
  class Game
    SECONDS_PER_HOUR = 60*60
    NUM_PLAYERS = 6
    SECONDS_PER_ROLL = 60
    ROLLS_PER_HOUR = SECONDS_PER_HOUR/SECONDS_PER_ROLL
    HOURS_OF_PLAY = 4
    NUM_ROUNDS = NUM_PLAYERS * (HOURS_OF_PLAY * ROLLS_PER_HOUR)
    BET_UNIT=25
    TABLE_LIMIT=5000
    DOUBLE_EVERY_OTHER_HIT = ->(stats, winnings) { stats.num_wins.even? ? stats.amount : 0 }

    attr_reader :players, :dice, :total_rounds, :shooter

    def initialize(num_players: NUM_PLAYERS, total_rounds: NUM_ROUNDS)
      @players = create_players(num_players)
      @dice = Dice.new
      @next_player = 0
      @total_rounds = total_rounds
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
      total_rounds.times do
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


  class Odds
    attr_reader :pays, :for_every, :vig

    def initialize(pays, for_every, vig: 0)
      @pays = pays
      @for_every = for_every
      @vig = vig
    end

    def payout(bet_amount)
      win_amt = (bet_amount / for_every ) * pays
      vig_amt = vig > 0 ? (amt * vig).floor : 0
      win_amt - vig_amt
    end

    PAYS_EVEN = new(1, 1)
    PAYS_2_1  = new(2, 1)
    PAYS_2_1_VIG_05  = new(2, 1, vig: 0.05)
    PAYS_DOUBLE = PAYS_2_1
    PAYS_6_5 = new(6, 5)
    PAYS_7_6 = new(7, 6)
    PAYS_7_5 = new(7, 5)
    PAYS_3_2 = new(3, 2)
    PAYS_TRIPLE = new(3, 1)
    PAYS_7_1 = new(7, 1)
    PAYS_9_1 = new(9, 1)
  end


  class Bet
    PLACE_4 = :place_4
    PLACE_5 = :place_5
    PLACE_6 = :place_6
    PLACE_8 = :place_8
    PLACE_9 = :place_9
    PLACE_10 = :place_10
    PASS_LINE_BET = :pass_line
    PASS_4 = :pass_4
    PASS_5 = :pass_5
    PASS_6 = :pass_6
    PASS_8 = :pass_8
    PASS_9 = :pass_9
    PASS_10 = :pass_odds_10
    PASS_ODDS_4 = :pass_odds_4
    PASS_ODDS_5 = :pass_odds_5
    PASS_ODDS_6 = :pass_odds_6
    PASS_ODDS_8 = :pass_odds_8
    PASS_ODDS_9 = :pass_odds_9
    PASS_ODDS_10 = :pass_odds_10
    HARD_4 = :hard_4
    HARD_8 = :hard_8
    HARD_6 = :hard_6
    HARD_10 = :hard_10
    FIELD_BET = :field

    attr_reader :name, :wins_on, :loses_on, :payers, :for_every, :max_odds, :prop

    def initialize(name, wins_on, loses_on, payers, max_odds: nil, prop: false)
      @name = name 
      @wins_on = wins_on
      @loses_on = loses_on
      @payers = payers
      @max_odds = max_odds
      @prop = prop
    end

    def evaluate(player_roll, bet_amount)
      if loses_on[player_roll]
        -bet_amount
      elsif wins_on[player_roll]
        winnings(player_roll, bet_amount)
      else
        0
      end
    end

    def winnings(player_roll, bet_amount)
      payer = payers.is_a?(Hash) ? payers[player_roll.val] : payers
      payer.payout(bet_amount)
    end

    def valid?(amount)
      return false if amount > Game::TABLE_LIMIT
      return false if amount < Game::BET_UNIT
      true
    end

    def prop?
      prop
    end

    ROLL_ONE_OF = ->(*nums) { ->(roll) {Array[*nums].include?(roll.val)} }
    WINS_ON = ROLL_ONE_OF
    LOSES_ON = ROLL_ONE_OF
    SEVEN_OUT = LOSES_ON[7]
    LOSES_EASY = ->(number) { ->(roll) { roll.val == 7 || !roll.hard(number) } }
    WINS_ON_HARD = ->(number) { ->(roll) { roll.hard(number) } }

    PLACE = {
       4 => new(PLACE_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_2_1_VIG_05),
       5 => new(PLACE_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_7_5),
       6 => new(PLACE_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_7_6),
       8 => new(PLACE_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_7_6),
       9 => new(PLACE_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_7_5),
      10 => new(PLACE_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_2_1_VIG_05),
    }
    PASS_LINE = new(PASS_LINE_BET, WINS_ON[[7,11]], LOSES_ON[2,3,12], Odds::PAYS_EVEN)
    PASS_POINT = {
       4 => new(PASS_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_EVEN),
       5 => new(PASS_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_EVEN),
       6 => new(PASS_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_EVEN),
       8 => new(PASS_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_EVEN),
       9 => new(PASS_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_EVEN),
      10 => new(PASS_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_EVEN)
    }
    PASS_ODDS = {
       4 => new(PASS_ODDS_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_2_1, max_odds: 3),
       5 => new(PASS_ODDS_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_3_2, max_odds: 4),
       6 => new(PASS_ODDS_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_6_5, max_odds: 5),
       8 => new(PASS_ODDS_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_6_5, max_odds: 5),
       9 => new(PASS_ODDS_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_3_2, max_odds: 4),
      10 => new(PASS_ODDS_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_2_1, max_odds: 3)
    }
    HARDWAYS = {
       4 => new(HARD_4,  WINS_ON_HARD[4],  LOSES_EASY[4], Odds::PAYS_7_1, prop: true),
       6 => new(HARD_6,  WINS_ON_HARD[6],  LOSES_EASY[6], Odds::PAYS_7_1, prop: true),
       8 => new(HARD_8,  WINS_ON_HARD[8],  LOSES_EASY[8], Odds::PAYS_9_1, prop: true),
      10 => new(HARD_10, WINS_ON_HARD[10], LOSES_EASY[10], Odds::PAYS_9_1, prop: true)
    }

    FIELD_ODDS = Hash.new(Odds::PAYS_EVEN).merge(2 => Odds::PAYS_DOUBLE, 12 => Odds::PAYS_TRIPLE)

    FIELD = new(FIELD_BET, WINS_ON[*2..4, *9..12], LOSES_ON[*5..8], FIELD_ODDS, prop: true)

    def to_s
      name.to_s
    end

    def inspect
      to_s
    end
  end


  class BetState
    #
    # state
    #   :on - in play, and pressable
    #   :off - temporarily not in play.  Can go to :on or :down
    #   :down - player took the bet off the table, but it retains stats
    #   :won - player won the bet.
    #   :lost - player lost the bet.
    attr_reader :profit, :count, :num_wins, :bet_amount, :state

    def initialize(amount)
      @count = 0 # number of rolls this bet had current_amount > 0
      @num_wins = 0 # number of times this bet won during a player turn
      @bet_amount = 0 # current amount of money on the bet
      @profit = 0
      @state = :on

      press(amount)
    end

    def on?
      state == :on
    end

    def off?
      state == :off
    end

    def active?
      on? || off?
    end

    def off!
      @state = :off
    end

    def on!
      @state = :on
    end

    def down!
      @state = :down
    end

    def press(amount)
      # pos or neg amounts ok
      must_be_on!
      @bet_amount += amount
      @profit -= amount
      down! if bet_amount == 0
    end
    
    def roll
      @count += 1 if on?
    end

    def payout(amount_won, parlay_amount = 0)
      must_be_on!
      @num_wins += 1
      @profit += (amount_won - parlay_amount)
      @bet_amount += parlay_amount
    end

    def lost!
      # preserve the last bet_amount to know the amount on the table
      must_be_on!
      @state = :lost
    end

    def won!
      @state = :won
    end

    def must_be_on!
      raise "bet is not ON" unless on?
    end
  end


  class PlayerBet
    attr_reader :player_turn, :craps_bet, :press_strategy, :state

    def initialize(player_turn, craps_bet, amount, press_strategy: nil)
      @craps_bet = craps_bet
      @player_turn = player_turn
      @press_strategy = press_strategy

      validate!(amount)

      @state = BetState.new(amount)
    end

    def evaluate(player_roll)
      state.roll

      result_amount = craps_bet.evaluate(player_roll, state.bet_amount)

      if result_amount > 0
        press_amount = press_strategy ? press_strategy[state, result_amount] : 0
        state.payout(result_amount, press_amount)
        state.won! if craps_bet.prop?
      elsif result_amount < 0
        state.lost
      end
      result_amount
    end

    def ensure_bet_amount(amount)
      return if amount == bet_amount

      state.press(amount - bet_amount)
    end

    def take_down
      ensure_bet_amount(0)
    end

    def validate!(amount)
      raise "Invalid bet amount #{amount} for #{craps_bet}" unless craps_bet.valid?(amount)
    end
  end


  class PlayerBets
    attr_reader :player_turn, :player_bets

    def initialize(player_turn)
      @player_turn = player_turn
      @player_bets = Hash.new {|h,k| h[k] = []}
    end

    def ensure_bet(craps_bet, ensure_amount, press_strategy: DOUBLE_EVERY_OTHER_HIT)
      #
      # No action is take in the craps_bet exists at the given ensure_amount in the active state.
      # "On" bets that exist with a differing bet_amount are adjusted up or down to ensure_amount,
      # possibly taken down. Otherwise a new :on bet is created if the ensure_amount > 0
      #
      # At the end of the roll (7out), all bets should be in the :won, :lost, :off, or :down
      # states, and statistics can be derived from them
      #
      existing_active_bet = active_bet(craps_bet)

      if existing_active_bet &&
        if existing_active_bet.state.on?
          # the bet amount will be adjusted to equal the ensure_amount, possibly
          # taken down if ensure_amount is 0
          existing_active_bet.ensure_bet_amount(ensure_amount)
        end
      elsif ensure_amount > 0
        create_bet(craps_bet, ensure_amount, press_strategy: press_strategy)
      end
    end

    def ensure_pass_line(amount)
      ensure_bet(Bet::PASS_LINE, amount)
    end

    def ensure_pass_line_and_odds_on_point(point, odds_amount)
      pass_line = active_bet(Bet::PASS_LINE)
      pass_point = active_bet(Bet::PASS_POINT[point])

      return if pass_line.nil? && pass_point.nil?

      pass_line_amount = pass_line.nil? ? 0 : pass_line.bet_amount
      pass_line.take_down unless pass_line.nil?

      ensure_bet(Bet::PASS_POINT[point], pass_line_amount)
      ensure_bet(Bet::PASS_ODDS[point], odds_amount)
    end

    private

    def create_bet(craps_bet, amount, press_strategy:)
      PlayerBet.new(player_turn, craps_bet, amount, press_strategy: press_strategy).tap do |bet|
        bets[craps_bet.name].unshift(bet)
      end
    end

    def active_bet(craps_bet)
      candidate = bets[craps_bet.name][0]
      candidate && candidate.state.active? ? candidate : nil
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

    def initialize(dice)
      @dice = dice
      @val = nil
      @outcome = nil
    end

    def roll
      dice.roll
      @val = dice.val
    end

    def hard(hard_total)
      val == hard_total && dice.hard?
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
      format("%d%s%s", val, dice.hard? ? "h" : "", OUTCOME_SYMBOLS[outcome])
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
      @bets = PlayerBets.new(self)
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
      if table_state.off?
        player_bets.ensure_pass_line(Game::BET_UNIT)
      else
        player_bets.ensure_pass_line_and_odds_on_point(
          table_state.point,
          Game::BET_UNIT * Bets::PASS_ODDS[table_state.point].max_odds
        )
        ensure_place_bets(table_state)
      end
    end

    def ensure_place_bets(table_state)
      [5,6,8,9].select {|n| n != table_state.point}.each do |place_number|
        player_bets.ensure_bet(
          Bet::PLACE[place_number],
          Game::BET_UNIT,
          press_strategy: DOUBLE_EVERY_OTHER_HIT
        )
      end
    end

    def pay_bets(roll)
      losers = []
      bets.each do |bet|
        adjustment = bet.evaluate(roll)
        if adjustment < 0
          losers << bet
        end
      end

      losers.each do |bet|
        bets.lost(bet.craps_bet)
      end

      self
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
end

def run(**args)
  QuickCraps::Game.run(**args)
end
