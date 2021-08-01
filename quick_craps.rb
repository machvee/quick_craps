class QuickCraps
  attr_reader :players, :dice, :num_shooters

  def initialize(num_players: 5, num_shooters: 10)
    @players = create_players(num_players)
    @dice = Dice.new
    @next_player = 0
    @num_shooters = num_shooters
  end

  def next_player_turn
    @player = players[calc_next_player]
    turn = @player.new_player_turn(dice)

    play_craps(turn)
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
    @players.each do |p|
      puts "-"*60
      print p.name + ": "
      p.turns.max_by {|t| t.stats.outcome_counts[:rolls]}.print_stats
      puts "-"*60
    end
    puts ("="*60) + "\n"
    p dice.freq
    self
  end

  private

  def create_players(num_players)
    num_players.times.each_with_object([]) {|n, p| p << Player.new(name: "Player#{n}")}
  end

  def calc_next_player
    next_player_ind = @next_player
    if (@next_player += 1) == players.length
      @next_player = 0
    end
    next_player_ind
  end

  def play_craps(turn)
    CrapsGame.new(turn).play!
  end
end

class CrapsGame
  OFF = 0
  ON = 1
  WINNERS=[7,11]
  POINTS=[4,5,6,8,9,10]
  CRAPS=[2,3,12]

  attr_reader :point, :player_turn, :state

  def initialize(player_turn)
    @player_turn = player_turn
    set_off
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
        set_on(roll.val)
        roll.point_established
      when *CRAPS
        roll.craps
      end
    when ON
      case roll.val
      when 7
        roll.seven_out
        set_off
        keep_rolling = false
      when *POINTS
        if roll.val == point
          roll.point_winner
          set_off
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

  def set_on(val)
    @point = val
    @state = ON
    self
  end

  def set_off
    @point = nil
    @state = OFF
    self
  end
end

class PlayerRoll
  POINT_ESTABLISHED = :point
  FRONT_LINE_WINNER = :front_line_winner
  POINT_WINNER      = :point_winner
  PLACE_WINNER      = :place_winner
  CRAPS             = :craps
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

  def initialize(val)
    @val = val
    @outcome = nil
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
    "#{val}#{OUTCOME_SYMBOLS[outcome]}"
  end

  def inspect
    to_s
  end
end

class PlayerTurnStats
  attr_reader :outcome_counts, :place_counts, :point_counts

  def initialize(player_turn)
    @player_turn = player_turn
    @outcome_counts = Hash.new(0)
    @point_counts = Hash.new(0)
    @place_counts = Hash.new(0)
  end

  def tally(roll)
    raise "no outcome yet" if roll.outcome.nil?
    outcome_counts[:rolls] += 1
    outcome_counts[roll.outcome] += 1

    case roll.outcome
    when PlayerRoll::PLACE_WINNER
      @place_counts[roll.val] += 1
    when PlayerRoll::POINT_WINNER
      @point_counts[roll.val] += 1
    end
  end

  def print_stats
    p outcome_counts
    print "points: ", point_counts, "\n"
    print "place: ", place_counts, "\n"
  end
end

class PlayerTurn
  attr_reader :player, :rolls, :stats

  def initialize(player)
    @player = player
    @rolls = []
    @stats = PlayerTurnStats.new(self)
  end

  def roll
    PlayerRoll.new(player.roll).tap do |r|
      rolls << r
    end
  end

  def keep_stats(roll)
    stats.tally(roll)
  end

  def print_stats
    p rolls
    stats.print_stats
  end
end

class Player
  attr_reader :name
  attr_reader :turns

  def initialize(name:)
    @name = name
    @turns = []
  end

  def new_player_turn(dice)
    @dice = dice
    PlayerTurn.new(self).tap do |turn|
      @turns << turn
    end
  end

  def roll
    @dice.roll
  end

  def inspect
    "#{name}: #{turns.length} turns.  Best: TBD"
  end
end

class Die
  NUM_FACES=6
  RANGE=1..NUM_FACES

  attr_reader :val

  def initialize(set_to=nil)
    if set_to
      set_to(val)
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
  attr_reader :val, :freq

  def initialize(num_dies=2)
    @dies = num_dies.times.each_with_object([]) {|n, o| o << Die.new}
    @freq = Array.new(max_sum + 1)
    reset
  end

  def roll
    shake
    keep_stats
    val
  end

  def to_s
    format("%2d %s", val, @dies.inspect)
  end

  def inspect
    to_s
  end

  def reset
    @freq.fill(0)
    shake
  end

  def num_rolls
    freq.sum
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
    freq[val] += 1
  end
end

def run(**args)
  QuickCraps.run(**args)
end
