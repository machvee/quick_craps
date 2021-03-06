#
# QuickCraps - plays 1000's of shooter turns at a table, for hours at a time, and keeps stats on their rolls/turns.
#    Learn quickly how length of a shooters roll will translate to $$ win/loss.
#    Provide procs that determine how to bet and how to press on Pass Line, Place, Hardways, and Field
#    and compare strategies
#
module QuickCraps
  class Game
    SECONDS_PER_HOUR = 60*60
    SECONDS_PER_ROLL = 60

    DFLT_NUM_PLAYERS = 6
    DFLT_HOURS_OF_PLAY = 4

    ROLLS_PER_HOUR = SECONDS_PER_HOUR/SECONDS_PER_ROLL
    DFLT_NUM_ROUNDS = DFLT_HOURS_OF_PLAY * ROLLS_PER_HOUR
    BET_UNIT=25
    DEFAULT_BUYIN=(40 * BET_UNIT)
    TABLE_LIMIT=5000
    DOUBLE_EVERY_OTHER_HIT = ->(stats, winnings) { stats.num_wins.even? ? stats.amount : 0 }

    attr_reader :players, :dice, :total_turns, :shooter

    def initialize(num_players: DFLT_NUM_PLAYERS, hours_of_play: DFLT_HOURS_OF_PLAY, seed: Random.new_seed)
      @players = create_players(num_players, buyin: DEFAULT_BUYIN)
      @next_player = 0
      @hours_of_play = hours_of_play
      @total_turns = @hours_of_play * ROLLS_PER_HOUR
      @shooter = nil
      @seed = seed
      @dice = Dice.new(seed: @seed, stats_keepers: dice_stats_keepers)
    end

    def next_player_turn
      @shooter = players[calc_next_player]
      play_craps
    end

    def self.run(**args)
      g = new(**args)
      g.run
      g.stats
    end

    def run
      total_turns.times do
        next_player_turn
      end
    end

    def stats
      {
        seed: @seed,
        players: players.map(&:stats),
        hours_of_play: @hours_of_play,
        total_turns: total_turns,
        dice: dice.stats
      }
    end

    def inspect
      "#{players.length} players, #{dice.total_rolls} rolls of dice"
    end

    private

    def create_players(num_players, buyin:)
      num_players.times.each_with_object([]) do |n, p|
        p << Player.new(name: "Player#{n+1}", buyin: buyin)
      end
    end

    def calc_next_player
      next_player_ind = @next_player
      if (@next_player += 1) == players.length
        @next_player = 0
      end
      next_player_ind
    end

    def play_craps
      ShooterRollsUntilSevenOut.new(shooter.new_player_turn(dice)).play!
    end

    def dice_stats_keepers
      [6,7,8,12].map {|n| ConsecutiveNumberStatsKeeper.new(n)}
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

    def round_up_bet_amount_if_needed(bet_amount)
      return bet_amount if bet_amount % for_every == 0

      ((bet_amount + for_every)/for_every) * for_every
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
    attr_reader :name, :wins_on, :loses_on, :bet_payer, :for_every, :max_odds, :prop

    def initialize(name, wins_on, loses_on, bet_payer, max_odds: nil, prop: false)
      @name = name 
      @wins_on = wins_on
      @loses_on = loses_on
      @bet_payer = bet_payer
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
      payer = bet_payer.is_a?(Hash) ? bet_payer[player_roll.val] : bet_payer
      payer.payout(bet_amount)
    end

    def valid?(amount)
      return false unless (Game::BET_UNIT..Game::TABLE_LIMIT).include?(amount)
      true
    end

    def appropriate_bet_amount(bet_amount)
      return bet_amount if bet_payer.is_a?(Hash) # FIELD pays for 1

      bet_payer.round_up_bet_amount_if_needed(bet_amount)
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
       4 => new(:place_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_2_1_VIG_05),
       5 => new(:place_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_7_5),
       6 => new(:place_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_7_6),
       8 => new(:place_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_7_6),
       9 => new(:place_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_7_5),
      10 => new(:place_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_2_1_VIG_05),
    }
    PASS_LINE = new(:pass_line, WINS_ON[[7,11]], LOSES_ON[2,3,12], Odds::PAYS_EVEN)
    PASS_POINT = {
       4 => new(:pass_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_EVEN),
       5 => new(:pass_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_EVEN),
       6 => new(:pass_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_EVEN),
       8 => new(:pass_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_EVEN),
       9 => new(:pass_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_EVEN),
      10 => new(:pass_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_EVEN)
    }
    MAX_ODDS = {
      4 => 3,
      5 => 4,
      6 => 5,
      8 => 5,
      9 => 4,
      10 => 3
    }
    PASS_ODDS = {
       4 => new(:pass_odds_4,  WINS_ON[4],  SEVEN_OUT, Odds::PAYS_2_1, max_odds: MAX_ODDS[4]),
       5 => new(:pass_odds_5,  WINS_ON[5],  SEVEN_OUT, Odds::PAYS_3_2, max_odds: MAX_ODDS[5]),
       6 => new(:pass_odds_6,  WINS_ON[6],  SEVEN_OUT, Odds::PAYS_6_5, max_odds: MAX_ODDS[6]),
       8 => new(:pass_odds_8,  WINS_ON[8],  SEVEN_OUT, Odds::PAYS_6_5, max_odds: MAX_ODDS[8]),
       9 => new(:pass_odds_9,  WINS_ON[9],  SEVEN_OUT, Odds::PAYS_3_2, max_odds: MAX_ODDS[9]),
      10 => new(:pass_odds_10, WINS_ON[10], SEVEN_OUT, Odds::PAYS_2_1, max_odds: MAX_ODDS[10])
    }
    HARDWAYS = {
       4 => new(:hard_4,  WINS_ON_HARD[4],  LOSES_EASY[4], Odds::PAYS_7_1, prop: true),
       6 => new(:hard_6,  WINS_ON_HARD[6],  LOSES_EASY[6], Odds::PAYS_7_1, prop: true),
       8 => new(:hard_8,  WINS_ON_HARD[8],  LOSES_EASY[8], Odds::PAYS_9_1, prop: true),
      10 => new(:hard_10, WINS_ON_HARD[10], LOSES_EASY[10], Odds::PAYS_9_1, prop: true)
    }

    FIELD_ODDS = Hash.new(Odds::PAYS_EVEN).merge(2 => Odds::PAYS_DOUBLE, 12 => Odds::PAYS_TRIPLE)

    FIELD = new(:field_bet, WINS_ON[*2..4, *9..12], LOSES_ON[*5..8], FIELD_ODDS, prop: true)

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
    #
    #   profit is the amount commited to the bet from the Players rail
    #   
    #
    attr_reader :profit_loss, :start_bet_amount, :current_bet_amount, :winnings, :state

    def initialize(amount, init_state: :on)
      @state = init_state
      @start_bet_amount = amount
      @current_bet_amount = amount
      @winnings = 0
      @profit_loss = -current_bet_amount
    end

    def on?
      state == :on
    end

    def off?
      state == :off
    end

    def lost?
      @state == :lost
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

    def down!(amount = @current_bet_amount + @winnings)
      # deduct amount first from winnings, then any remainder
      # from @current_bet_amount
      deduction = amount
      win_deduction = [winnings, amount].min
      @winnings -= win_deduction
      @profit_loss += win_deduction
      deduction -= win_deduction

      if deduction > 0
        @current_bet_amount -= deduction
        raise "invalid down! amount #{amount}" if @current_bet_amount < 0
        @profit_loss += deduction
      end

      @state = :down if @current_bet_amount == 0
    end

    def won!(amount_won)
      @winnings += amount_won
    end

    def lost!
      @state = :lost
    end

    def press!(press_amount = @winnings)
      # press the current_bet_amount by amount, 
      # using any and all winnings first.   Take
      # or add to profit based on how much winnings
      # covered the press amount (e.g. power press)
      @current_bet_amount += press_amount
      @winnings -= press_amount
      @profit_loss += winnings
      @winnings = 0
    end

    def stats
      {
        state: state,
        start_bet_amount: start_bet_amount,        
        current_bet_amount: current_bet_amount,
        profit: profit_loss
      }
    end


    def inspect
      stats.to_s
    end
  end


  class BetEventHandler
    attr_reader  :events, :state

    def initialize(player_bet)
      @player_bet = player_bet
      @events = []
    end

    def fire!(event_name, **args)
      events << {name: event_name, **args}
      case event_name
      when :make_bet
        # user makes his initial bet, establishing start state
        @state = BetState.new(args[:amount])
      when :press_bet
        state.press!(args[:amount])
      when :won
        state.won!(args[:amount])
      when :take_profit
        state.down!(args[:amount])
      when :on
        state.on!
      when :off
        state.off!
      when :take_down
        state.down!
      when :lost
        state.lost!
      end
    end

    def inspect
      events.to_s
    end
  end


  class PlayerBet
    attr_reader :bet, :event_handler

    def initialize(bet, amount)
      @bet = bet
      adjusted_amount = bet.appropriate_bet_amount(amount)

      validate!(adjusted_amount)

      @event_handler = BetEventHandler.new(self)

      event_handler.fire!(:make_bet, amount: adjusted_amount)
    end

    def state
      event_handler.state
    end

    def evaluate(player_roll)
      return 0 if state.off?

      bet_outcome_amount = bet.evaluate(player_roll, state.current_bet_amount)

      if bet_outcome_amount > 0
        event_handler.fire!(:won, amount: bet_outcome_amount)
      elsif bet_outcome_amount < 0
        event_handler.fire!(:lost)
      end
      bet_outcome_amount
    end

    def on!
      state.on!
    end

    def off!
      state.off!
    end

    def active?
      state.active?
    end

    def take_down
      state.down!
    end

    def validate!(amount)
      raise "Invalid bet amount #{amount} for #{bet}" unless bet.valid?(amount)
    end

    def stats
      state
    end

    def inspect
      stats.inspect
    end
  end


  class PlayerBets
    attr_reader :table_bets

    def initialize
      @table_bets = Hash.new {|h,k| h[k] = []}
    end

    def each_active_bet
      table_bets.each do |name, bet_array|
        last_bet = bet_array.last
        next if last_bet.nil? || !last_bet.active?

        yield last_bet
      end
    end

    def ensure_bet(bet, amount)
      create_bet(bet, amount) if !active_bet(bet)
    end

    def ensure_pass_line(amount)
      ensure_bet(Bet::PASS_LINE, amount)
    end

    def ensure_pass_point_and_odds(point, pass_line_amount, odds_amount)
      pass_line = active_bet(Bet::PASS_LINE)
      pass_point = active_bet(Bet::PASS_POINT[point])

      return if pass_line.nil? && pass_point.nil?

      pass_line.take_down unless pass_line.nil?

      ensure_bet(Bet::PASS_POINT[point], pass_line_amount)
      ensure_bet(Bet::PASS_ODDS[point], odds_amount)
    end

    def stats
      {}.tap do |bet_stats|
        table_bets.each do |bet_name, bets|
          bet_stats[bet_name] = bets.map(&:stats)
        end
      end
    end

    def inspect
      stats.inspect
    end

    private

    def create_bet(bet, amount)
      PlayerBet.new(bet, amount).tap do |player_bet|
        table_bets[bet.name].push(player_bet)
      end
    end

    def active_bet(bet)
      candidate = table_bets[bet.name].last
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


  class ShooterRollsUntilSevenOut
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
      player_turn.make_bet_decisions(table_state)

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

      player_turn.resolve_bet_outcomes(roll)

      player_turn.keep_stats(roll, table_state)

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
    attr_reader :is_hard

    def initialize(dice)
      @dice = dice
      @val = nil
      @outcome = nil
      @is_hard = false
    end

    def roll
      dice.roll
      @is_hard = dice.hard?
      @val = dice.val
      self
    end

    def hard(hard_total)
      val == hard_total && is_hard
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
      format("%d%s%s", val, is_hard ? "h" : "", OUTCOME_SYMBOLS[outcome])
    end

    def inspect
      to_s
    end
  end


  class PlayerTurnStatsKeeper
    attr_reader :outcome_counts, :place_counts, :point_counts, :start_rail, :turn_number

    def initialize(player, turn_number)
      @outcome_counts     = Hash.new(0)
      @place_counts       = Hash.new(0)
      @point_counts       = Hash.new(0)
      @turn_number        = turn_number
      @start_rail         = player.rail # starting player rail
      @longest_point      = 0
      @point_roll_counter = 0
    end

    def tally(player_roll, table_state)
      raise "no outcome yet" if player_roll.outcome.nil?

      outcome_counts[:total_rolls] += 1
      outcome_counts[player_roll.outcome] += 1

      case player_roll.outcome
      when PlayerRoll::PLACE_WINNER
        place_counts[player_roll.val] += 1
        @point_roll_counter += 1
      when PlayerRoll::POINT_ESTABLISHED
        @point_roll_counter = 0
      when PlayerRoll::POINT_WINNER
        point_counts[player_roll.val] += 1
        @point_roll_counter += 1
        if @longest_point < @point_roll_counter
          @longest_point = @point_roll_counter
        end
      else
        @point_roll_counter += 1 if table_state.on?
      end
    end

    def to_hash
      {
        turn:          turn_number,
        outcomes:      outcome_counts,
        point_winners: point_counts,
        place_winners: place_counts,
        longest_point: @longest_point,
        money: {
          start: start_rail,
        }
      }
    end
  end


  class PlayerTurn
    attr_reader :dice, :player, :rolls, :stats_keeper, :player_bets

    def initialize(player, dice, turn_number)
      @dice = dice
      @player = player
      @rolls = []
      @player_bets = PlayerBets.new
      @stats_keeper = PlayerTurnStatsKeeper.new(player, turn_number)
    end

    def roll
      PlayerRoll.new(dice).tap do |r|
        rolls << r.roll
      end
    end

    def keep_stats(roll, table_state)
      stats_keeper.tally(roll, table_state)
    end

    def stats
      stats_keeper.to_hash
    end

    def make_bet_decisions(table_state)
      # 
      # possible actions:
      #   make new bets
      #   take down any profits from bet winnings from previous rolls
      #   press bets from rail or winnings from previous rolls
      #   take down bets
      #   mark bets on/off
      if table_state.off?
        player_bets.ensure_pass_line(Game::BET_UNIT)
      else
        player_bets.ensure_pass_point_and_odds(
          table_state.point,
          Game::BET_UNIT,
          Game::BET_UNIT * Bet::PASS_ODDS[table_state.point].max_odds
        )
        ensure_place_bets(table_state)
      end
    end

    def ensure_place_bets(table_state)
      [5,6,8,9].select {|n| n != table_state.point}.each do |place_number|
        player_bets.ensure_bet(Bet::PLACE[place_number], Game::BET_UNIT)
      end
    end

    def resolve_bet_outcomes(roll)
      player_bets.each_active_bet do |active_bet|
        active_bet.evaluate(roll)
      end
      self
    end

    def inspect
      stats.to_s
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
        buyin:                  @player.buyin,
        rail:                   @player.rail,
        roll_lengths:           calculated_roll_lengths,
        longest_roll:           longest_roll_stats,
        avg_rolls_before_7_out: @player.average_rolls_before_7_out
      }
    end

    def longest_roll_stats
      longest_turn = @player.longest_turn
      {
        rolls: longest_turn.rolls.inspect,
        longest_stats: longest_turn.stats
      }
    end

    def calculated_roll_lengths
      @player.turns.each {|t| @roll_lengths[t.stats[:outcomes][:total_rolls]] += 1 }
      @roll_lengths.sort_by {|k,v| k}.to_h
    end
  end


  class Player
    attr_reader :name
    attr_reader :turns
    attr_reader :dice
    attr_reader :buyin
    attr_reader :rail

    def initialize(name:, buyin:)
      @name = name
      @turns = []
      @buyin = buyin
      @rail = buyin
    end

    def new_player_turn(dice)
      PlayerTurn.new(self, dice, turns.length + 1).tap do |turn|
        @turns << turn
      end
    end

    def stats
      PlayerStats.new(self).to_hash
    end

    def longest_turn
      turns.max_by {|t| t.stats[:outcomes][:total_rolls]}
    end

    def average_rolls_before_7_out
      turns.sum {|t| t.stats[:outcomes][:total_rolls]} / turns.length
    end

    def inspect
      "#{name}: #{turns.length} turns"
    end
  end

  class Die
    NUM_FACES=6
    RANGE=1..NUM_FACES

    attr_reader :val

    def initialize(prng: Random.new)
      @prng = prng
      roll
    end

    def roll
      @val = @prng.rand(RANGE)
    end

    def inspect
      @val.to_s
    end
  end


  class Dice
    attr_reader :val, :total_rolls
    attr_reader :stats_keepers

    BIG_NUM = 2**128

    def initialize(num_dies=2, seed:, stats_keepers: [])
      main_prng = Random.new(seed)
      @dies = num_dies.times.each_with_object([]) do |n, o|
        die_prng = Random.new(main_prng.rand(BIG_NUM))
        o << Die.new(prng: die_prng)
      end
      @freqs = Array.new(max_sum + 1)
      @stats_keepers = stats_keepers
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
      stats_keepers.each(&:reset)
      shake
    end

    def [](offset)
      raise "invalid die number #{offset}"  unless (0...@dies.length).include?(offset)
      @dies[offset].val
    end

    def stats
      {
        total_rolls: @total_rolls,
        frequency: @freqs[2..-1].map.with_index(2) {|v, i| [i, v]}.to_h
      }.merge(
        stats_keepers.length > 0 ? stats_keepers.map {|k| [k.name, k.to_s]}.to_h : {}
      )
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

      stats_keepers.each do |keeper|
        keeper.tally(self)
      end
    end
  end
end

class ConsecutiveNumberStatsKeeper
  attr_reader :name
  attr_reader :number

  def initialize(number)
    @name = "consecutive #{number}'s"
    @number = number
    reset
  end

  def tally(dice)
    if dice.val == number
      @count += 1
    else
      if @max < @count
        @max = @count
      end
      @count = 0
    end
  end

  def to_s
    @max.to_s
  end

  def reset
    @max = 0
    @count = 0
  end
end

def run(**args)
  QuickCraps::Game.run(**args)
end
