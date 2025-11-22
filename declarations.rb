#class CharacterStatus; end
#class StatusManager; end
#class CharacterStats; end
#class Character; end
#class Check; end
#class RunTests; end
#class PlayTest; end
#class Menu; end
#class MenuOptions; end
#module Display; end

class DataStore; end
class Serializable; end
module Tools; end

class Display; end
class Menu; end
module MenuManual; end
module MenuSelectMonsters; end
module MenuCommonFunctions; end
module MenuInitiative; end
module MenuCombat; end


class EmptyAction; end
class SkillAction < EmptyAction; end
class WeaponAction < EmptyAction; end
class ConjuredAction < WeaponAction; end


class CombatAction; end
class ConjuredAction < WeaponAction; end
class WeaponAction < EmptyAction; end

class Attack; end

class BaseRoll < Serializable; end
class Roll < BaseRoll; end
class Check < Roll; end
class InitiativeRoll < BaseRoll; end

class Gender < Serializable; end
class Equipment < Serializable; end
class ConjuredEquipment < Equipment; end

class Damage < Serializable; end

class CharacterStatus < Serializable; end
class CharacterSheet < Serializable; end
class Identity < Serializable; end
class Progression < Serializable; end
class AbilityScores < Serializable; end
class SpecialAbilities < Serializable; end
module SkillMath; end
module CharMath; end


class CombatMath; end
module RulesMath; end

module ResetCharacters; end

