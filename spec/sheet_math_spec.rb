require 'spec_helper'
require 'sheet_math'
require_relative 'creatures/fixtures'

# The math the tablet's "?" shows (docs/project/android_app.md → Character
# sheet). SheetMath only words what the domains computed, so every
# explanation has to end on the number the sheet shows.
RSpec.describe SheetMath do
  include CreaturesFixtures

  let(:accessor) { Creatures::Accessor.new(korth) } # Dwarven Cleric 4, Tier 2
  let(:vitals)   { CreatureSheet.build(accessor)[:vitals] }

  describe '.vitals' do
    subject(:math) { described_class.vitals(accessor, vitals) }

    it 'explains every vital the sheet shows' do
      expect(math.keys).to eq(%i[hp mana toxicity damage_reduction damage_resilience combat_pool])
      math.each_value { |m| expect(m).to include(:title, :lines) }
    end

    it "shows Hit Points as the Tier's formula with its values filled in" do
      con = accessor.attribute_value(:con)
      expect(math[:hp]).to eq(title: 'Hit Points', lines: ["Tier 2: 2 × #{con} CON = #{accessor.max_hit_points}"])
    end

    it 'adds the damage taken and temporary Hit Points' do
      state = Conditions.store.state_for(accessor.id)
      state.hp_damage = { minor: 3, major: 2 }
      max = accessor.max_hit_points
      math = described_class.hit_points(accessor, vitals.merge(temp_hp: 4))
      expect(math[:lines].drop(1)).to eq(["#{max} − 5 damage = #{max - 5}", '+4 temporary'])
    ensure
      state.hp_damage = {}
    end

    it 'builds Mana from the Tier formula and each Class' do
      int = accessor.attribute_value(:int)
      expect(math[:mana][:lines]).to eq(
        ["Tier 2: #{int} INT = #{int}", 'Cleric 4 × 4 per level = 16', "#{int} + 16 = #{accessor.max_mana}"]
      )
    end

    it 'shows the Toxicity Threshold, with Tier 0 counted as 0.5' do
      cha = accessor.attribute_value(:cha)
      expect(math[:toxicity]).to eq(title: 'Magic Toxicity',
                                    lines: ["Threshold: #{cha} CHA × Tier 2 = #{vitals[:toxicity][:threshold]}"])

      commoner = Creatures::Accessor.new(record(id: 9010, tier: 0))
      low = described_class.toxicity(commoner, CreatureSheet.build(commoner)[:vitals])
      expect(low[:lines]).to eq(['Threshold: 10 CHA × 0.5 (Tier 0) = 5'])
    end

    it 'lays the Combat Pool out as the Budget and the price table' do
      b    = vitals[:combat_pool_breakdown]
      pool = math[:combat_pool]
      expect(pool[:lines].last).to end_with("= #{b[:budget]} Budget")
      expect(pool[:table][:head]).to eq(%w[Dice Each Cost Left])
      expect(pool[:table][:rows].length).to eq(b[:blocks].length)
      expect(pool[:table][:rows].first[1]).to eq('free')
      expect(pool[:table][:foot]).to eq(["#{b[:size]} dice", '', b[:cost].to_s, b[:remaining].to_s])
      expect(pool[:note]).to eq("Next die costs #{b[:next_die_cost]}")
    end
  end

  describe '.defense' do
    it 'lists one source per line and totals more than one' do
      one = described_class.defense('Damage Reduction', total: 3, components: [{ amount: 3, label: 'Chain mail' }])
      expect(one[:lines]).to eq(['3 Chain mail'])

      many = described_class.defense('Damage Resilience', total: 4, components: [
        { amount: 2, label: 'tier' }, { amount: 2, label: 'rage' }, { amount: 1, label: 'bless', applied: false }
      ])
      expect(many[:lines]).to eq(['2 tier', '+ 2 rage', '+ 1 bless (does not stack)', '= 4'])
    end

    it 'says so when nothing adds to it' do
      expect(described_class.defense('Damage Reduction', total: 0, components: [])[:lines]).to eq(['No sources'])
    end
  end

  describe 'Attributes' do
    let(:row) { CreatureSheet.build(accessor)[:attributes_table].find { |r| r[:key] == :con } }

    it "sums the score's parts" do
      math = described_class.attribute(row)
      expect(math[:title]).to eq('Constitution')
      expect(math[:lines]).to eq(["#{accessor.base_attribute_value(:con)} base + 2 racial + 4 inherent = #{row[:score]}"])
    end

    it 'says when Conditions change the score' do
      math = described_class.attribute(row.merge(score: 5))
      expect(math[:lines].last).to eq('Conditions make it 5')
    end

    it 'takes a Check from half the Attribute' do
      lines = described_class.check(row)[:lines]
      expect(lines.first).to eq("Prowess: #{row[:score]} CON ÷ 2 = #{row[:half]}")
      expect(lines.grep(/\ADice: /).first).to end_with("= #{row[:check][:dice]}")
    end

    it "takes a Save from each Class's rate for it" do
      lines = described_class.save(accessor, row)[:lines]
      expect(lines.first).to match(/\ACleric 4 · \w+: .* = #{accessor.ranks_for('con_save')} ranks\z/)
      expect(lines.grep(/\ADice: /).first).to end_with("= #{row[:save][:dice]}")
    end
  end

  describe '.skill' do
    it 'names the rate a trained Skill advances at' do
      lines = described_class.skill(accessor, 'invocation')[:lines]
      expect(lines.first).to eq('Cleric 4 · Aligned: floor(5 × level ÷ 3) = 6 ranks')
      wis = accessor.attribute_value(:wis)
      expect(lines[1]).to eq("Prowess: 6 ranks + #{wis / 2} (#{wis} WIS ÷ 2) = #{6 + (wis / 2)}")
    end

    it 'says what an untrained Skill would advance at, and its penalty' do
      lines = described_class.skill(accessor, 'stealth')[:lines]
      expect(lines.first).to eq('Cleric 4 · not trained (Unaligned: level if trained)')
      expect(lines.grep(/\AUntrained: −2/)).not_to be_empty
    end

    it 'adds up the ranks of more than one Class' do
      multi = Creatures::Accessor.new(record(
        id: 9011, classes: { fighter: { level: 4, skills: %w[athletics] }, rogue: { level: 3, skills: %w[athletics] } }
      ))
      lines  = described_class.skill(multi, 'athletics')[:lines]
      a, b   = multi.rank_sources('athletics').map { |s| s[:ranks] }
      expect(lines[2]).to eq("#{a} + #{b} = #{a + b} ranks")
    end

    it 'shows the Floor Ability and the Substitution Ability at work' do
      bard = Creatures::Accessor.new(birch) # Bard 4: Jack of All Trades, Versatile Performance
      expect(described_class.skill(bard, 'stealth')[:lines]).to include('Jack Of All Trades: at least 2 ranks')
      expect(described_class.skill(bard, 'deception')[:lines].first).to eq('Versatile Performance: Perform (Sing) stands in')
    end

    it 'ends every Skill on the dice and the TN its Roll uses' do
      [korth, brenna, vex, birch].each do |rec|
        acc = Creatures::Accessor.new(rec)
        CreatureSheet.all_skills(acc).each do |s|
          roll  = CreatureSheet.skill_roll(acc, s[:key])
          lines = described_class.skill(acc, s[:key])[:lines]
          where = "#{rec[:name]} #{s[:key]}"
          expect(lines.grep(/\ADice: /).first).to end_with("= #{roll[:dice_count]}"), where
          expect(lines.grep(/\ATN: /).first[/\d+\z/].to_i).to eq(roll[:tn]), where
        end
      end
    end

    it 'is nil when it cannot be built' do
      expect(described_class.skill(Object.new, 'stealth')).to be_nil
    end
  end

  describe 'wording' do
    it 'fills a formula in with its values' do
      expect(described_class.formula_text('2 * con', con: 17)).to eq('2 × 17 CON')
      expect(described_class.formula_text('(con + level) / 2', con: 17, level: 4)).to eq('(17 CON + 4 level) ÷ 2')
    end

    it "shows the rate formulas the ranks are computed with" do
      Creatures::Config.proficiency_advancement_rates.each do |name, formula|
        rate = name.downcase.to_sym
        expect(described_class.rate_text(rate)).to start_with("#{name}: ")
        (1..20).each do |level|
          shown = Creatures::Formula.eval(formula.sub(/\Afloor\((.*)\)\z/, '\1'), level: level)
          expect(shown).to eq(Proficiencies::Ranks.apply_rate(level, rate)), "#{name} at level #{level}"
        end
      end
    end

    it 'shows the TN, and the Starting Value once the TN hits a limit' do
      cfg  = DiceResolution.config
      base = cfg.base_target_number
      expect(described_class.target_number_lines([])).to eq(["TN: #{base}"])
      expect(described_class.target_number_lines([['Competency', 2]])).to eq(["TN: #{base} − 2 = #{base - 2}"])

      low = described_class.target_number_lines([['Competency', base - cfg.minimum_target_number + 2]])
      expect(low).to eq(["TN: #{base} − #{base - cfg.minimum_target_number + 2} = #{cfg.minimum_target_number - 2}, " \
                         "raised to #{cfg.minimum_target_number}", 'Starts with 2 free successes'])

      high = described_class.target_number_lines([['Competency', -(cfg.maximum_target_number - base + 1)]])
      expect(high).to eq(["TN: #{base} + #{cfg.maximum_target_number - base + 1} = #{cfg.maximum_target_number + 1}, " \
                          "lowered to #{cfg.maximum_target_number}", 'Starts with 1 failure'])
    end

    it 'says when same-type bonuses do not stack' do
      lines = described_class.target_number_lines([['Competency', 2], ['Competency', 1]])
      expect(lines.first).to eq('Bonuses of one type do not stack')
    end
  end
end
