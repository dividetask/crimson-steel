require 'json'

module Tools
  def self.load_json(filename)
    file_path = File.join(File.dirname(__FILE__), 'data', filename)
    return [] unless File.exist?(file_path)
    JSON.parse(File.read(file_path))
  end

  def self.save_json(filename, data)
    file_path = File.join(File.dirname(__FILE__), 'data', filename)
    File.write(file_path, JSON.pretty_generate(data))
  end

  def self.next_item_id
    items = load_json('equipment.json')
    return 1 if items.empty?
    items.map { |i| i['item_id'].to_i }.max + 1
  end

  # Loads equipment.json and materializes a stable item_id for every entry.
  # Items without a persisted item_id get a synthetic id that skips any id
  # already in use elsewhere in the file, so they never shadow a purchased
  # item with the same persisted id. Assignment is deterministic given the
  # file contents, so the same call in different processes produces the
  # same ids.
  def self.load_equipment_with_ids
    items = load_json('equipment.json')
    taken = items.map { |i| i['item_id'].to_i }.reject(&:zero?).to_set
    next_synth = 1
    items.each do |item|
      next if item['item_id']
      next_synth += 1 while taken.include?(next_synth)
      item['item_id'] = next_synth
      taken << next_synth
      next_synth += 1
    end
    items
  end
end
