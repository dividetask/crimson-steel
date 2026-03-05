require_relative '../helpers'
require_relative 'spec_tools.rb'
require 'json'

RSpec.describe CharacterSheet do
  let(:character_list) { SpecData.get_characters }

  describe '#character_sheet_view' do
    context 'Lookup details' do
      it 'has skills, attributes, hp and mana methods defined' do
        character = CharacterSheet.new(character_list.first)
        method_list = [:name, :race, :full_klass, :tier, :bab, :combat_pool, :initiative, :damage_reduction,
          :damage_resilience, :speed, :hp_max, :mana_max, :mana_regen, :ability_score_names, :score, :half_mod,
          :attr_dice, :add_plus, :save_dice, :skill_list, :clean_skill_name, :skill_ranks, :skill_dice]
        method_list.each do |method_sym|
          expect(character).to respond_to(method_sym),
            "Expected CharacterSheet to have method :#{method_sym}"
        end
      end

      it 'returns skills, attributes, hp and mana with realistic values' do
        character_list.each do |character_data|
          character = CharacterSheet.new(character_data)

          SpecData.simple_test(character.name, String, {length: {min: 2}})
          SpecData.simple_test(character.race, String, {length: {min: 2}})
          SpecData.simple_test(character.full_klass, String, {length: {min: 2}})
          SpecData.simple_test(character.tier, Integer, {value: {min: 0, max: 9}})
          SpecData.simple_test(character.bab, Integer, {value: {min: 0, max: 100}})
          SpecData.simple_test(character.combat_pool, Integer, {value: {min: 0, max: 100}})
          SpecData.simple_test(character.initiative, Integer, {value: {min: 0, max: 50}})
          SpecData.simple_test(character.damage_reduction, Integer, {value: {min: 0, max: 100}})
          SpecData.simple_test(character.damage_resilience, Integer, {value: {min: 0, max: 100}})
          SpecData.simple_test(character.speed, Integer, {value: {min: 5, max: 100}})
          SpecData.simple_test(character.hp_max, Integer, {value: {min: 1, max: 200}})
          SpecData.simple_test(character.mana_max, Integer, {value: {min: 1, max: 800}})
          SpecData.simple_test(character.mana_regen, Integer, {value: {min: 1, max: 200}})
          character.ability_score_names.each do |name, sym|
            SpecData.simple_test(character.score(sym), Integer, {value: {min: 1, max: 100}})
            SpecData.simple_test(character.half_mod(sym), Integer, {value: {min: 0, max: 50}})
            SpecData.simple_test(character.attr_dice(sym), Integer, {value: {min: 4, max: 8}})
            SpecData.simple_test(character.add_plus(:attr_bonus, sym), String, {value: {prefix: ['+', '-']}})
            SpecData.simple_test(character.save_dice(sym), Integer, {value: {min: 4, max: 10}})
            SpecData.simple_test(character.add_plus(:save_bonus, sym), String, {value: {prefix: ['+', '-']}})
          end

          character.skill_list.each do |skill_name|
            SpecData.simple_test(character.clean_skill_name(skill_name), String, {length: {min: 2}})
            SpecData.simple_test(character.skill_ranks(skill_name), Integer, {value: {min: 0, max: 100}})
            SpecData.simple_test(character.skill_dice(skill_name), Integer, {value: {min: 6, max: 10}})
            SpecData.simple_test(character.add_plus(:skill_bonus,skill_name), String, {value: {prefix: ['+', '-']}})
          end
        end
      end
    end
  end
end
