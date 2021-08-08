class QuickCraps
  DEFAULT_NUM_PLAYERS = 6
  DEFAULT_NUM_SHOOTERS = DEFAULT_NUM_PLAYERS * 1000
  DEFAULT_BET_UNIT=25
  DOUBLE_EVERY_OTHER_HIT = ->(bet_hit_count, current_bet) { bet_hit_count.even? ? current_bet * 2 : current_bet }

  attr_reader :players, :dice, :num_shooters, :shooter

  def initialize(num_players: DEFAULT_NUM_PLAYERS, num_shooters: DEFAULT_NUM_SHOOTERS, bet_unit: DEFAULT_BET_UNIT)
    @players = create_players(num_players)
    @dice = Dice.new
    @next_player = 0
    @num_shooters = num_shooters
    @shooter = nil
    @press_stragegy = DOUBLE_EVERY_OTHER_HIT
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


class Round
  OFF = 0
  ON = 1
  WINNERS=[7,11]
  POINTS=[4,5,6,8,9,10]
  CRAPS=[2,3,12]

  attr_reader :point, :player_turn, :state

  def initialize(player_turn)
    @player_turn = player_turn
    set_table_off
  end

  def play!
    while player_roll; end
  end

  def player_roll
    roll = player_turn.roll

    keep_rolling = true

    case state
    when OFF
      case roll.val
      when *WINNERS
        roll.winner
      when *POINTS
        set_table_on(roll.val)
        roll.point_established
      when *CRAPS
        roll.craps
      end
    when ON
      case roll.val
      when 7
        roll.seven_out
        set_table_off
        keep_rolling = false
      when *POINTS
        if roll.val == point
          roll.point_winner
          set_table_off
        else
          roll.place_winner
        end
      else # 2,3,11,12
        roll.horn_winner
      end
    end

    player_turn.keep_stats(roll)

    keep_rolling
  end

  def set_table_on(val)
    @point = val
    @state = ON
    self
  end

  def set_table_off
    @point = nil
    @state = OFF
    self
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


class PlayerTurnBetMaker
  attr_reader :player_turn, :pass, :pass_odds, :place, :hard_ways

  def initialize(player_turn)
    @player_turn = player_turn
  end
end


class PlayerTurn
  attr_reader :dice, :player, :rolls, :stats_keeper

  def initialize(player, dice)
    @dice = dice
    @player = player
    @rolls = []
    @stats_keeper = PlayerTurnStatsKeeper.new
    @bet_maker = PlayerTurnBetMaker.new(self)
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
end


class PlayerStats
  def initialize(player)
    @player = player
  end

  def to_hash
    {
      name:                   @player.name,
      longest_roll:           longest_roll_stats,
      avg_rolls_before_7_out: @player.turns.sum {|t| t.stats[:outcomes][:total_rolls]} / @player.turns.length
    }
  end

  def longest_roll_stats
    longest_turn = @player.turns.max_by {|t| t.stats[:outcomes][:total_rolls]}
    {
      rolls: longest_turn.rolls.inspect,
      stats: longest_turn.stats
    }
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
