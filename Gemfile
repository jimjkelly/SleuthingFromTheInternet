ruby '2.2.1'
source 'http://rubygems.org' 
gem 'sinatra'
gem 'rake'
gem 'json'
gem 'thin'
gem "sinatra-activerecord"
gem "activerecord"
gem "activesupport"
gem "nokogiri"
gem "aws-ses"

group :production do
        gem 'activerecord-postgresql-adapter'
	gem 'newrelic_rpm'
end

group :development do
	gem "byebug"
	gem "sqlite3"
        gem "Rack"
end
