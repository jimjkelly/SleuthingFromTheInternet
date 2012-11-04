# Add the current directory to the load path
$:.unshift File.dirname(__FILE__)
require 'sinatra'
require 'sinatra/activerecord'
require 'db/models'
require 'logger'
require 'rubygems'
require 'bundler'
require 'uri'

Bundler.setup
Bundler.require

Time.zone = "UTC"
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = "UTC"

configure :development do
  ActiveRecord::Base.establish_connection(:adapter => "sqlite3",
                                          :database  => "db/development.db")
end

configure :production do
  db = URI.parse(ENV['DATABASE_URL'] || 'postgres://localhost/mydb')
    
  ActiveRecord::Base.establish_connection(
    :adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
    :host     => db.host,
    :username => db.user,
    :password => db.password,
    :database => db.path[1..-1],
    :encoding => 'utf8'
  )
end
