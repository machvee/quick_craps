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
      ok {actual} == 5
    end

    spec "has expected die one value" do
      actual = @dice[1]
      ok {actual} == 3
    end

    spec "#roll with seed value has expected outcome [3,1]" do
      actual = @dice.roll
      ok {actual} == 4
      ok {@dice.hard?}.falsy?
    end

    topic "hard rolls" do
      before do
        13.times {@dice.roll}
      end

      spec "#roll 13 times yeilds known hard 4" do
        ok {@dice.hard?}.truthy?
        ok {@dice.val} == 4
      end
    end
  end

end

