class ReallyQuickCraps
  def initialize(num_rolls: 100)
    @num_rolls = num_rolls
    @stats = Hash.new(0)
    @p = nil
    @hot = 0
  end

  def run
    off = ->(r) {
      @stats[:cor] += 1
      @hot += 1

      case r
      when 2,3,12
        @stats[:crp] += 1
        "x"
      when 7,11
        @stats[:flw] += 1
        "!"
      else
        @stats[:pte] += 1
        @p = r
        "*"
      end
    }

    on = ->(r) {
      @hot += 1
      case r
      when 7
        @stats[:pso] += 1
        @p = nil
        if @hot > @stats[:hot]
          @stats[:hot] = @hot
        end
        @hot = 0
        "x"
      when @p
        @stats[:ptw] += 1
        @p = nil
        "!"
      when 4,5,6,8,9,10
        @stats[:plw] += 1
        ""
      else
        @stats[:hrn] += 1
        ""
      end
    }
    rolls = Array.new(@num_rolls) { rand(1..6) + rand(1..6) }
    rolls << 7 if rolls.last != 7
    rolls.map do |r|
      "%d%s" % [r, @p ? on[r] : off[r]]
    end
  end

  def stats
    @stats.inspect
  end
end

def r(nr = 2000)
  g = ReallyQuickCraps.new(num_rolls: nr)
  a = g.run
  p a
  g.stats
end
