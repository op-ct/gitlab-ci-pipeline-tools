# GEM_SERVERS | a space/comma delimited list of rubygem servers
gem_sources   = ENV.key?('GEM_SERVERS') ? ENV['GEM_SERVERS'].split(/[, ]+/) : ['https://rubygems.org']
gem_sources.each { |gem_source| source gem_source }

gem 'bundler'
gem 'dotenv'
gem 'gitlab'
gem 'json'

group :debug do
  gem 'pry'
  gem 'pry-byebug'
  gem 'pry-doc'
end

#vim: set syntax=ruby:
