require 'creatures'
require 'proficiencies'

# Monster Creation domain — backs the DM's "Quick Monster" builder on the
# DM Page. It stands up a stub enemy Creature fast, mid-session, when the
# party meets something that isn't in the roster: pick a name, race, and
# (optionally) a class + level, set the six attributes, and save. The new
# Creature is tagged as an enemy template (`enemy_template` + `category:custom`)
# so it lands in the Roster's enemy list and can be added to Combat like any
# other template.
#
# "Full control over abilities, limited to existing abilities" means the
# builder assembles the Creature from the game's existing catalogs — its
# racial abilities come from the chosen Race, its class abilities from the
# chosen Class and Level, its proficiencies from the chosen trained Skills —
# rather than inventing new powers. Casters can be refined afterward through
# the normal Creature data / Character Creation flow.
module MonsterCreation
  # New monsters persist to the enemy roster overlay (data/ overlay).
  ENEMY_SOURCE = 'creatures_data_enemies.yaml'.freeze
  # Custom monsters file under their own category so they group together in
  # the Roster's enemy list.
  CATEGORY = 'custom'.freeze
  DEFAULT_ATTRIBUTE = 10

  module_function

  # The data the Quick Monster form needs: selectable races, classes, and
  # the Skill catalog (for the optional trained-Skill picks).
  def blob
    {
      races:      races,
      classes:    classes,
      skills:     skills,
      attributes: attribute_keys,
      default_attribute: DEFAULT_ATTRIBUTE
    }
  end

  # Every known Race, humanized and sorted — monsters may be any race
  # (orc, goblin, ogre, …), not only the playable ones.
  def races
    Creatures::Races.data.keys.sort.map { |key| { key: key, label: humanize(key) } }
  end

  def race?(key)
    Creatures::Races.known?(key.to_s)
  end

  def classes
    Creatures::Advancement.classes.keys.sort.map { |key| { key: key, label: humanize(key) } }
  end

  def class?(key)
    Creatures::Advancement.classes.key?(key.to_s)
  end

  # Concrete (non-Set) Skill keys, humanized and sorted, for the trained
  # Skill picker. Bare Set Skills (keys ending in `_`) are excluded because
  # a Creature must carry the resolved family member, not the family key.
  def skills
    Proficiencies.skills.keys.map(&:to_s).reject { |k| k.end_with?('_') }.sort
                 .map { |key| { key: key, label: humanize(key) } }
  end

  def attribute_keys
    Creatures::Config.attribute_keys.map(&:to_s)
  end

  # Build and persist a new enemy Creature from the form params (string-keyed).
  # Returns the new Creature's integer id. Raises ArgumentError on bad input.
  #
  # Keys:
  #   'name'       — required display name.
  #   'race'       — required known race key.
  #   'class'      — optional class key; when present, 'level' applies.
  #   'level'      — class level (default 1). Ignored without a class.
  #   'tier'       — optional explicit Tier (integer). Omitted → derived.
  #   'hide_tier'  — truthy to withhold the Tier from players.
  #   'attributes' — { attr_key => integer }; missing keys default to 10.
  #   'skills'     — [concrete skill key, …] trained Skills for the class.
  #   'token'      — optional creature token image path.
  def create!(params)
    name = params['name'].to_s.strip
    raise ArgumentError, 'a monster name is required' if name.empty?

    race = params['race'].to_s
    raise ArgumentError, "#{race.inspect} is not a known race" unless race?(race)

    loose = {
      'id'         => Creatures::Dataset.next_id,
      'name'       => name,
      'race'       => race,
      'group'      => 'enemy',
      'tags'       => ['enemy_template', "category:#{CATEGORY}"],
      'attributes' => build_attributes(params['attributes'])
    }

    tier = params['tier'].to_s.strip
    loose['tier'] = Integer(tier) unless tier.empty?
    loose['hide_tier'] = true if truthy?(params['hide_tier'])

    token = params['token'].to_s.strip
    loose['metadata'] = { 'creature_token' => token } unless token.empty?

    class_key = params['class'].to_s
    unless class_key.empty?
      raise ArgumentError, "unknown class #{class_key.inspect}" unless class?(class_key)
      level  = params['level'].to_s.strip
      level  = level.empty? ? 1 : Integer(level)
      skills = Array(params['skills']).map(&:to_s).reject(&:empty?)
      loose['advancement'] = {
        'classes' => { class_key => { 'level' => level, 'skills' => skills } }
      }
    end

    record = Creatures::Record.normalize(loose, source: ENEMY_SOURCE)
    record[:source] = ENEMY_SOURCE
    Creatures::Dataset.insert!(record)
    record[:id]
  rescue ArgumentError
    raise
  rescue StandardError => e
    raise ArgumentError, e.message
  end

  def build_attributes(raw)
    raw = raw.is_a?(Hash) ? raw : {}
    attribute_keys.each_with_object({}) do |k, h|
      v = raw[k] || raw[k.to_sym]
      h[k] = v.to_s.strip.empty? ? DEFAULT_ATTRIBUTE : Integer(v)
    end
  end

  def truthy?(value)
    %w[1 true on yes].include?(value.to_s.strip.downcase)
  end

  def humanize(key)
    key.to_s.split(/[_\s]+/).reject(&:empty?).map { |w| w[0].upcase + w[1..].to_s }.join(' ')
  end
end
