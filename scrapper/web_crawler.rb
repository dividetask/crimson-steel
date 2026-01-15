#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'nokogiri'
require 'json'

class WebCrawler
  def initialize(start_url, max_pages: 10)
    @start_url = start_url
    @max_pages = max_pages
    @visited = Set.new
    @data = []
  end

  def crawl
    queue = [@start_url]
    
    while !queue.empty? && @visited.size < @max_pages
      url = queue.shift
      next if @visited.include?(url)
      
      puts "Crawling: #{url}"
      @visited.add(url)
      
      begin
        page_data = fetch_page(url)
        @data << page_data
        
        # Find and queue new links from the same domain
        new_links = page_data[:links].select { |link| same_domain?(link, @start_url) }
        queue.concat(new_links - @visited.to_a)
        
        sleep 1 # Be polite, don't hammer the server
      rescue => e
        puts "Error crawling #{url}: #{e.message}"
      end
    end
    
    @data
  end

  def fetch_page(url)
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)
    
    if response.is_a?(Net::HTTPSuccess)
      doc = Nokogiri::HTML(response.body)
      
      {
        url: url,
        title: doc.css('title').text.strip,
        headings: doc.css('h1, h2, h3').map(&:text).map(&:strip),
        paragraphs: doc.css('p').map(&:text).map(&:strip).reject(&:empty?),
        links: doc.css('a').map { |a| normalize_url(a['href'], uri) }.compact.uniq,
        images: doc.css('img').map { |img| img['src'] }.compact
      }
    else
      { url: url, error: "HTTP #{response.code}" }
    end
  end

  def normalize_url(href, base_uri)
    return nil if href.nil? || href.empty? || href.start_with?('#', 'javascript:', 'mailto:')
    
    begin
      URI.join(base_uri, href).to_s
    rescue
      nil
    end
  end

  def same_domain?(url, base_url)
    URI.parse(url).host == URI.parse(base_url).host
  rescue
    false
  end

  def save_to_json(filename = 'crawled_data.json')
    File.write(filename, JSON.pretty_generate(@data))
    puts "\nData saved to #{filename}"
  end

  def print_summary
    puts "\n" + "="*50
    puts "Crawl Summary"
    puts "="*50
    puts "Pages crawled: #{@visited.size}"
    puts "Total data entries: #{@data.size}"
    
    @data.each_with_index do |page, idx|
      puts "\n#{idx + 1}. #{page[:url]}"
      puts "   Title: #{page[:title]}" if page[:title]
      puts "   Headings: #{page[:headings]&.size || 0}"
      puts "   Paragraphs: #{page[:paragraphs]&.size || 0}"
      puts "   Links: #{page[:links]&.size || 0}"
    end
  end
end

# Command line interface
if ARGV.empty?
  puts "Usage: ruby web_crawler.rb <url> [max_pages]"
  puts "Example: ruby web_crawler.rb https://example.com 20"
  exit 1
end

url = ARGV[0]
max_pages = (ARGV[1] || 10).to_i

crawler = WebCrawler.new(url, max_pages: max_pages)
crawler.crawl
crawler.print_summary
crawler.save_to_json
