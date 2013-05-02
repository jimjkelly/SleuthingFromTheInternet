# Add the current directory to the load path
$:.unshift File.dirname(__FILE__)
require 'sinatra'
require 'sinatra/activerecord'
require 'securerandom'
require 'db/models'
require 'rubygems'
require 'aws/ses'
require 'bundler'
require 'logger'
require 'uri'

Bundler.setup
Bundler.require

Time.zone = "UTC"
ActiveRecord::Base.time_zone_aware_attributes = true
ActiveRecord::Base.default_timezone = :utc

configure :development do
  ActiveRecord::Base.establish_connection(:adapter => "sqlite3",
                                          :database  => "db/development.db")
end

configure :development do
  enable :logging, :dump_errors
  set :logging, Logger::DEBUG
  set :raise_errors, true
  set :database, 'sqlite:///db/development.db'
end

configure :production do
  require 'newrelic_rpm'
  
  db = URI.parse(ENV['DATABASE_URL'])

  ActiveRecord::Base.establish_connection(
    :adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
    :host     => db.host,
    :port     => db.port,
    :username => db.user,
    :password => db.password,
    :database => db.path[1..-1],
    :encoding => 'utf8'
  )
end
