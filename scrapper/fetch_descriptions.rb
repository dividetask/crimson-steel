#!/usr/bin/env ruby

require 'open-uri'
require 'nokogiri'
require 'json'

def fetch_descriptions(fetch_count)
  # Load spells.json
  unless File.exist?('spells.json')
    puts "Error: spells.json not found!"
    exit 1
  end

  spells = JSON.parse(File.read('spells.json'))
  
  # Find spells that need descriptions (no description and not failed)
  spells_to_fetch = spells.select { |s| s['description'].nil? && !s['failed'] }
  
  puts "Total spells: #{spells.size}"
  puts "Need to fetch: #{spells_to_fetch.size}"
  
  if spells_to_fetch.empty?
    puts "Nothing to fetch!"
    return false
  end
  
  # Limit to fetch_count
  spells_to_process = spells_to_fetch.first(fetch_count)
  puts "Fetching #{spells_to_process.size} spells\n\n"
  
  spells_to_process.each_with_index do |spell, index|
    print "[#{index + 1}/#{spells_to_process.size}] #{spell['text']}... "
    
    begin
      html = URI.open(spell['url']).read
      doc = Nokogiri::HTML(html)
      
      divider = doc.css('p.divider').find { |p| p.text.strip == 'DESCRIPTION' }
      
      if divider
        description_p = divider.next_element
        
        if description_p && description_p.name == 'p'
          spell['description'] = description_p.text.strip
          puts "✓"
        else
          spell['failed'] = true
          puts "✗ (no <p> after divider)"
        end
      else
        spell['failed'] = true
        puts "✗ (no DESCRIPTION divider)"
      end
      
      sleep 0.5
      
    rescue => e
      spell['failed'] = true
      puts "✗ (#{e.message})"
    end
  end
  
  # Save
  File.write('spells.json', JSON.pretty_generate(spells))
  puts "\nSaved to spells.json"
  return true
end

# Main
#if ARGV.empty?
  #puts "Usage: ruby fetch_descriptions.rb <count>"
  #puts "Example: ruby fetch_descriptions.rb 100"
  #exit 1
#end

#fetch_count = ARGV[0].to_i
fetch_count = 10
while fetch_descriptions(fetch_count)
  true
end

