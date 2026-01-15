#!/usr/bin/env ruby

require 'open-uri'
require 'nokogiri'
require 'json'

#if ARGV.empty?
  #puts "Usage: ruby spell_scraper.rb <url>"
  #puts "Example: ruby spell_scraper.rb https://www.d20pfsrd.com/magic/spell-lists-and-domains/spell-lists-sorcerer-and-wizard/"
  #exit 1
#end

url = 'https://www.d20pfsrd.com/magic/spell-lists-and-domains/spell-lists-sorcerer-and-wizard/'
#url = ARGV[0]

# Fetch and parse the page
puts "Fetching #{url}..."
html = URI.open(url).read
doc = Nokogiri::HTML(html)



# Find all spell links and their levels
spells = []
current_level = nil

# Iterate through the document looking for captions and spell links
doc.traverse do |node|
  # Check if this is a caption with spell level
  if node.name == 'caption'
    span = node.at_css('span[id]')
    if span && span['id']
      # Extract the first character from the id (e.g., "0_Level" -> "0")
      current_level = span['id'][0]
      puts "Found level: #{current_level}"
    end
  end
  
  # Check if this is a spell link
  if node.name == 'a' && node['class'] == 'spell'
    parent_td = node.ancestors.find { |n| n.name == 'td' && n['class'] == 'text' }
    if parent_td
      spells << {
        text: node.text.strip,
        url: node['href'],
        level: current_level
      }
    end
  end
end

# Save to JSON
File.write('spells.json', JSON.pretty_generate(spells))





puts "Found #{spells.size} spells"
puts "Saved to spells.json"
