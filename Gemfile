ruby '2.6.6'
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
gem "rest-client"

group :production do
        gem 'activerecord-postgresql-adapter'
	gem 'newrelic_rpm'
end

group :development do
	gem "byebug"
	gem "sqlite3"
        gem "Rack"
end
