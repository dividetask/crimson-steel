ATTACK_SUCCESS_THRESHOLD = 2
WEAPON_THRESHOLDS_DEFAULTS = {pierce: 4, bludgeoning: 3, slashing: 5}
WEAPON_THRESHOLDS = {slam: 3, bite: 5, rapier: 4, club: 3, scimitar: 5, quarterstaff: 3, battleaxe: 5, greataxe: 5, longbow: 4, javelin: 4, punch: 6, maul: 3, shortbow: 4, dagger: 4}
WEAPON_BLEEDMOD_DEFAULTS = {pierce: 3, bludgeoning: 5, slashing: 7}
WEAPON_BLEEDMOD = {slam: 5, bite: 3, rapier: 3, club: 5, scimitar: 7, quarterstaff: 5, battleaxe: 7, greataxe: 7, longbow: 3, javelin: 3, punch: 1, shortbow: 3, maul: 5, dagger: 3}
EQUIPMENT_DR = {armor: {light: 1, natural: 2, medium: 3, heavy: 6}}
WEAPON_CATEGORY = {greataxe: :heavy, battleaxe: :medium_1h, longbow: :ranged, slam: :light, bite: :light, maul: :heavy, shortbow: :ranged, punch: :light, dagger: :light, rapier: :medium_1h}
WEAPON_DAMAGE_TYPE = {greataxe: :slashing, battleaxe: :slashing, longbow: :pierce, slam: :bludgeoning, bite: :pierce, maul: :bludgeoning, shortbow: :pierce, punch: :bludgeoning, dagger: :pierce, rapier: :pierce}
ATTACK_TYPE = {heavy: :melee, medium_1h: :melee, light: :melee, ranged: :ranged}
WEAPON_STR_MOD = {heavy: 0.5, medium_2h: 0.5, medium_1h: 0.25, light: 0.25, ranged: 0.25}
WEAPON_BASE_MOD = {heavy: 2, medium_2h: 0, medium_1h: 0, light: -2, ranged: 0}
SPEED_MOD = {pierce: 0, slashing: 1, bludgeoning: 2, light: 0, medium_1h: 1, medium_2h: 1, heavy: 2, ranged: 2} 

class ConjuredEquipment < Equipment
  attr_reader :magic_properties, :caster

	def initialize(name, category, subcategory, bonus, magic_properties = {}, additional_properties = {}, equipped = false)
  	@caster = nil
    @magic_properties = magic_properties
    super(name, category, subcategory, bonus, additional_properties, equipped)
	end

  def set_caster(caster); @caster = caster; end
  def block_allies?; return @magic_properties[:block_allies] == true; end
  def needs_dice?; return @magic_properties[:needs_dice] == true; end
  def skill; return @magic_properties[:skill]; end
end

class Equipment < Serializable
  attr_reader :name, :category, :subcategory, :bonus, :additional_properties, :equipped

	def initialize(name, category, subcategory, bonus, additional_properties = {}, equipped = false)
		@name, @category, @subcategory, @bonus, @additional_properties, @equipped = name, category, subcategory, bonus, additional_properties, equipped
	end

	def get_threshold; @additional_properties[:threshold] || WEAPON_THRESHOLDS[@subcategory] || 0; end
	def get_bleed_mod; WEAPON_BLEEDMOD[@subcategory] || 0; end
  def is_melee; return ATTACK_TYPE[WEAPON_CATEGORY[@subcategory]] == :melee; end
  def get_attack_type; return ATTACK_TYPE[WEAPON_CATEGORY[@subcategory]]; end
  def get_weapon_category; return WEAPON_CATEGORY[@subcategory]; end
	def get_dr; base_dr = EQUIPMENT_DR.dig(@category,@subcategory); return 0 unless base_dr; return base_dr + @bonus; end
  def get_base_weapon_damage(char); wt = WEAPON_CATEGORY[@subcategory]; return (char.str * WEAPON_STR_MOD[wt]).to_i + WEAPON_BASE_MOD[wt]; end
  def speed; SPEED_MOD[WEAPON_CATEGORY[@subcategory]] + SPEED_MOD[WEAPON_DAMAGE_TYPE[@subcategory]]; end
end
