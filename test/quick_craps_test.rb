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
end

