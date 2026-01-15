#!/usr/bin/env ruby

require 'open-uri'
require 'nokogiri'
require 'json'

MAX_PER_RUN = 100

# Load the spells from spells.json
unless File.exist?('spells.json')
  puts "Error: spells.json not found!"
  puts "Run spell_scraper.rb first to generate the spell list."
  exit 1
end

spells = JSON.parse(File.read('spells.json'))

# Load existing progress if it exists
if File.exist?('spells_with_descriptions.json')
  existing_spells = JSON.parse(File.read('spells_with_descriptions.json'))
  puts "Loaded existing progress: spells_with_descriptions.json"
  
  # Merge existing descriptions back into the spell list
  existing_map = existing_spells.each_with_object({}) do |spell, hash|
    hash[spell['url']] = spell['description']
  end
  
  spells.each do |spell|
    if existing_map.key?(spell['url'])
      spell['description'] = existing_map[spell['url']]
    end
  end
else
  puts "No existing progress found, starting fresh"
end

# Find spells that need descriptions (don't have one yet)
spells_to_fetch = spells.select { |s| !s.key?('description') || s['description'].nil? }

puts "Total spells: #{spells.size}"
puts "Already have descriptions: #{spells.size - spells_to_fetch.size}"
puts "Need to fetch: #{spells_to_fetch.size}"

if spells_to_fetch.empty?
  puts "\nAll spells already have descriptions!"
  exit 0
end

# Limit to MAX_PER_RUN
spells_to_process = spells_to_fetch.first(MAX_PER_RUN)
puts "Processing #{spells_to_process.size} spells this run (max #{MAX_PER_RUN})\n\n"

failed_spells = []
processed_count = 0

spells_to_process.each_with_index do |spell, index|
  print "[#{index + 1}/#{spells_to_process.size}] #{spell['text']}... "
  
  begin
    # Fetch the spell page
    html = URI.open(spell['url']).read
    doc = Nokogiri::HTML(html)
    
    # Find the DESCRIPTION divider
    divider = doc.css('p.divider').find { |p| p.text.strip == 'DESCRIPTION' }
    
    if divider
      # Get the next <p> tag after the divider
      description_p = divider.next_element
      
      if description_p && description_p.name == 'p'
        spell['description'] = description_p.text.strip
        puts "✓"
        processed_count += 1
      else
        spell['description'] = nil
        failed_spells << spell['text']
        puts "✗ (no <p> after divider)"
      end
    else
      spell['description'] = nil
      failed_spells << spell['text']
      puts "✗ (no DESCRIPTION divider found)"
    end
    
    # Be polite - small delay between requests
    sleep 0.5
    
  rescue => e
    spell['description'] = nil
    failed_spells << spell['text']
    puts "✗ (error: #{e.message})"
  end
end

# Save updated spells with descriptions
File.write('spells_with_descriptions.json', JSON.pretty_generate(spells))

puts "\n" + "="*60
puts "Run Complete!"
puts "="*60
puts "Saved to: spells_with_descriptions.json"
puts "Successfully fetched this run: #{processed_count}/#{spells_to_process.size}"

remaining = spells.count { |s| !s.key?('description') || s['description'].nil? }
puts "\nOverall progress:"
puts "  Total spells: #{spells.size}"
puts "  With descriptions: #{spells.size - remaining}"
puts "  Still need: #{remaining}"

if remaining > 0
  puts "\nRun the script again to fetch more descriptions"
end

if failed_spells.any?
  puts "\nFailed to get descriptions for #{failed_spells.size} spells this run:"
  failed_spells.each do |name|
    puts "  - #{name}"
  end
end

