require 'irb'
require_relative 'declarations.rb'
require_relative 'datastore.rb'
require_relative 'combat.rb'
require_relative 'character.rb'
require_relative 'display.rb'
require_relative 'general.rb'
require_relative 'rules.rb'
require_relative 'tests.rb'



#run_tests = RunTests.new
#run_tests.single_step_spider_ambush
#run_tests.test_spider_ambush
run_tests = PlayTest.new
run_tests.fight_spiders 5

exit
#cultist = Character.get_cult_leaders_sheet
#lysander = Character.get_lysanders_sheet
#olga = Character.get_olgas_sheet
#basic_combat = BasicCombat.new(lysander, cultist, true)
#basic_combat.simulate_combat
