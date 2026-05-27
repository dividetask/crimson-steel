require 'fileutils'

module Chronicle
  # Holds Chronicle state in memory and persists every mutation back
  # to disk. Load order:
  #   1. data/chronicle_data.json (if present)
  #   2. docs/common/chronicle/chronicle_data.example.json
  #
  # On load the example file is treated as read-only; mutations are
  # always written to the data path.
  class Store
    DATA_PATH    = File.expand_path('../../data/chronicle_data.json', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/chronicle/chronicle_data.example.json', __dir__)

    attr_reader :data_path

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH)
      path = File.exist?(data_path) ? data_path : example_path
      raw = JSON.parse(File.read(path))
      new(raw, data_path: data_path)
    end

    def initialize(raw = {}, data_path: DATA_PATH)
      @data_path = data_path
      @campaign_name    = (raw['campaign_name'] || 'Untitled Campaign').to_s
      @timestamp        = normalize_timestamp(raw['timestamp'])
      @current_chapter  = Integer(raw['current_chapter'] || 1)
      @chapters         = (raw['chapters'] || []).map { |c| normalize_chapter(c) }
      @entries          = (raw['entries'] || []).map { |e| Entry.normalize(e) }
      @next_id          = Integer(raw['next_id'] || (max_entry_id + 1))
      backfill_positions!
    end

    # ---------- Snapshot / persistence ----------

    def to_h
      {
        'campaign_name'   => @campaign_name,
        'timestamp'       => { 'day_index' => @timestamp[:day_index], 'round_of_day' => @timestamp[:round_of_day] },
        'current_chapter' => @current_chapter,
        'chapters'        => @chapters.map { |c| { 'number' => c[:number], 'name' => c[:name] } },
        'entries'         => @entries,
        'next_id'         => @next_id
      }
    end

    def persist!
      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, JSON.pretty_generate(to_h))
      File.rename(tmp, @data_path)
    end

    # ---------- Campaign metadata ----------

    def campaign_name
      @campaign_name
    end

    def campaign_name=(name)
      @campaign_name = name.to_s
      persist!
      @campaign_name
    end

    def timestamp
      @timestamp.dup
    end

    def advance_time(rounds: 0, days: 0)
      @timestamp = Timekeeping.advance(@timestamp, rounds: rounds, days: days)
      persist!
      @timestamp.dup
    end

    # ---------- Chapters ----------

    def list_chapters
      @chapters.sort_by { |c| c[:number] }.map(&:dup)
    end

    def add_chapter(number:, name:)
      raise ArgumentError, "Chapter #{number} already exists" if @chapters.any? { |c| c[:number] == number }
      @chapters << { number: Integer(number), name: name.to_s }
      persist!
      @chapters.last.dup
    end

    def rename_chapter(number, name)
      c = @chapters.find { |x| x[:number] == number }
      raise ArgumentError, "Chapter #{number} does not exist" unless c
      c[:name] = name.to_s
      persist!
      c.dup
    end

    def remove_chapter(number)
      removed = @chapters.find { |c| c[:number] == number }
      return nil unless removed
      @chapters.delete(removed)
      persist!
      removed.dup
    end

    def current_chapter
      @current_chapter
    end

    def advance_chapter
      @current_chapter += 1
      persist!
      @current_chapter
    end

    def current_chapter=(number)
      @current_chapter = Integer(number)
      persist!
      @current_chapter
    end

    # ---------- Entries ----------

    def add_entry(attrs)
      h = Entry.stringify_keys(attrs)
      h['id']    = @next_id
      @next_id  += 1
      h['chapter']        ||= @current_chapter
      h['notes_position'] ||= next_notes_position(Integer(h['chapter']))
      h['scene_position'] ||= next_scene_position
      entry = Entry.normalize(h)
      @entries << entry
      persist!
      entry['id']
    end

    def edit_entry(id, updates)
      idx = @entries.index { |e| e['id'] == id }
      raise ArgumentError, "Entry #{id} does not exist" unless idx
      @entries[idx] = Entry.merge(@entries[idx], updates)
      persist!
      @entries[idx]
    end

    def delete_entry(id)
      removed = @entries.find { |e| e['id'] == id }
      return nil unless removed
      @entries.delete(removed)
      persist!
      removed
    end

    def get_entry(id)
      @entries.find { |e| e['id'] == id }
    end

    # Filters are conjunctive. Pass nil/absent to ignore a filter.
    def list_entries(chapter: nil, entry_type: nil, active_only: false, visible_to: nil)
      result = @entries.dup
      result.select! { |e| e['chapter'] == chapter }       if chapter
      result.select! { |e| e['entry_type'] == entry_type } if entry_type
      result.select! { |e| e['active'] }                   if active_only
      if visible_to
        result.select! { |e| visible?(e, viewing_creature_id: visible_to) }
      end
      result
    end

    # Visibility rule per docs/common/chronicle/chronicle_design.md.
    # When viewing_creature_id is nil we treat the viewer as the DM.
    def visible?(entry, viewing_creature_id: nil)
      return true if viewing_creature_id.nil?
      return false if (entry['hidden_from'] || []).include?(viewing_creature_id)
      return true if entry['shared']
      entry['owner_id'] == viewing_creature_id
    end

    # ---------- Reorder ----------

    def set_notes_position(id, position)
      entry = get_entry(id)
      raise ArgumentError, "Entry #{id} does not exist" unless entry
      shift_positions!(@entries.select { |e| e['chapter'] == entry['chapter'] && e['id'] != id },
                       'notes_position', position)
      entry['notes_position'] = Integer(position)
      persist!
      entry
    end

    def set_scene_position(id, position)
      entry = get_entry(id)
      raise ArgumentError, "Entry #{id} does not exist" unless entry
      shift_positions!(@entries.select { |e| e['active'] && e['id'] != id },
                       'scene_position', position)
      entry['scene_position'] = Integer(position)
      persist!
      entry
    end

    # ---------- Internal ----------

    private

    def normalize_timestamp(t)
      t ||= {}
      t = t.transform_keys(&:to_s) if t.respond_to?(:transform_keys)
      {
        day_index:    Integer(t['day_index'] || 0),
        round_of_day: Integer(t['round_of_day'] || 0)
      }
    end

    def normalize_chapter(c)
      c = c.transform_keys(&:to_s) if c.respond_to?(:transform_keys)
      { number: Integer(c.fetch('number')), name: (c['name'] || '').to_s }
    end

    def max_entry_id
      ids = (@entries || []).map { |e| e['id'].to_i }
      ids.empty? ? 0 : ids.max
    end

    def next_notes_position(chapter_number)
      siblings = @entries.select { |e| e['chapter'] == chapter_number && e['notes_position'] }
      siblings.empty? ? 1 : siblings.map { |e| e['notes_position'] }.max + 1
    end

    def next_scene_position
      siblings = @entries.select { |e| e['active'] && e['scene_position'] }
      siblings.empty? ? 1 : siblings.map { |e| e['scene_position'] }.max + 1
    end

    def shift_positions!(entries, field, threshold)
      entries.each do |e|
        cur = e[field]
        next unless cur && cur >= threshold
        e[field] = cur + 1
      end
    end

    def backfill_positions!
      # Notes positions, per Chapter.
      @entries.group_by { |e| e['chapter'] }.each_value do |group|
        next_pos = (group.map { |e| e['notes_position'] }.compact.max || 0) + 1
        group.each do |e|
          next if e['notes_position']
          e['notes_position'] = next_pos
          next_pos += 1
        end
      end
      # Scene positions, across all Active entries.
      active = @entries.select { |e| e['active'] }
      next_pos = (active.map { |e| e['scene_position'] }.compact.max || 0) + 1
      active.each do |e|
        next if e['scene_position']
        e['scene_position'] = next_pos
        next_pos += 1
      end
    end
  end
end
