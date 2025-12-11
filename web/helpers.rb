module CharacterHelpers
  def load_json(filename)
    file_path = File.join(settings.root, 'data', filename)
    JSON.parse(File.read(file_path)) if File.exist?(file_path)
  end

  def calculate_stats(character)
    scores = character['ability_scores']
    level = character['level']
    
    mods = {}
    scores.each do |ability, score|
      mod = (score - 10) / 2
      mods[ability] = { 'score' => score, 'mod' => mod, 'half' => mod / 2 }
    end
    
    # Calculate max HP
    con_mod = mods['con']['mod']
    hp_per_level = 6
    max_hp = hp_per_level * level + (con_mod * level)
    
    # Calculate current HP from damage
    current_hp = max_hp
    character['damage']&.each do |dmg|
      current_hp -= dmg['amount'] * { 'minor' => 1, 'moderate' => 5, 'major' => 10 }[dmg['severity']]
    end
    
    # Calculate mana
    max_mana = (mods['int']['half'] + mods['wis']['half']) * level
    current_mana = max_mana - (character['mana_used'] || 0)
    
    # Calculate skills
    skills = {}
    character['skill_progression']&.each do |skill, progression|
      ability_key = skill_ability_map[skill] || 'int'
      ability_mod = mods[ability_key]['half']
      ranks = progression * level / 3
      base_dice = 6 + ranks + ability_mod
      bonus = base_dice > 10 ? base_dice - 10 : 0
      base_dice = [base_dice, 10].min
      skills[skill] = { 'dice' => base_dice, 'bonus' => bonus, 'ranks' => ranks }
    end
    
    { 'mods' => mods, 'max_hp' => max_hp, 'current_hp' => current_hp,
      'max_mana' => max_mana, 'current_mana' => current_mana, 'skills' => skills }
  end

  def skill_ability_map
    { 'heal' => 'wis', 'sense_motive' => 'wis', 'arcana' => 'int',
      'survival' => 'wis', 'intimidate' => 'cha', 'perception' => 'wis',
      'athletics' => 'str', 'stealth' => 'dex' }
  end
end
