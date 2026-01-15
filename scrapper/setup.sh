#!/bin/bash

echo "Installing required Ruby gems..."
gem install nokogiri --user-install

echo ""
echo "Setup complete! You can now run the crawler:"
echo "  ruby web_crawler.rb https://example.com 10"
