require 'oktest'
require './quick_craps.rb'

Oktest.scope do

  topic QuickCraps::Dice do
    seed = 834831100909038

    before do
      @dice = QuickCraps::Dice.new(seed: seed)
    end

    spec "has expected die zero value" do
      actual = @dice[0]
      ok {actual} == 4
    end

    spec "has expected die one value" do
      actual = @dice[1]
      ok {actual} == 2
    end

    spec "#roll with seed value has expected outcome [5,6]" do
      actual = @dice.roll
      ok {actual} == 11
      ok {@dice.hard?}.falsy?
    end

    topic "hard rolls" do
      before do
        3.times {@dice.roll}
      end

      spec "#roll 13 times yields known hard 4" do
        ok {@dice.hard?}.truthy?
        ok {@dice.val} == 6
      end
    end
  end

  topic QuickCraps::BetState do
    before do
      @amount = 100
      @win_amount = 200
      @bs = QuickCraps::BetState.new(@amount)
    end

    spec "expected initial state and amounts" do
      ok {@bs.on?}.truthy?
      ok {@bs.off?}.falsy?
      ok {@bs.current_bet_amount} == @amount
      ok {@bs.profit_loss} == -@amount
    end

    topic "can be lost!" do
      before do
        @bs.lost!
      end

      spec "has expected profit" do
        ok {@bs.profit_loss} == -@amount
        ok {@bs.lost?}.truthy?
      end
    end


    topic "can be won!" do
      before do
        @bs.won!(@win_amount)
      end

      spec "has expected profit" do
        ok {@bs.winnings} == @win_amount
      end

      spec "is still on after win" do
        ok {@bs.on?}.truthy?
      end
    end

    topic "can be set off!" do
      before do
        @bs.off!
      end

      spec "can be set off" do
        ok {@bs.off?}.truthy?
      end
    end
  end
end

