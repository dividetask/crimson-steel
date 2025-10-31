#class CharacterStatus; end
#class StatusManager; end
#class CharacterStats; end
#class Character; end
#class Check; end
#class RunTests; end
#class PlayTest; end

class DataStore; end
class Serializable; end
class Menu; end
class MenuOptions; end
module Display; end
module Tools; end

class BaseRoll < Serializable; end
class Roll < BaseRoll; end
class Check < Roll; end
class InitiativeRoll < BaseRoll; end

class Gender < Serializable; end
class Equipment < Serializable; end

class Damage < Serializable; end

class CharacterStatus < Serializable; end
class CharacterSheet < Serializable; end
class Identity < Serializable; end
class Progression < Serializable; end
class AbilityScores < Serializable; end
module SkillMath; end
module CharMath; end


class CombatMath; end
module RulesMath; end

module ResetCharacters; end

