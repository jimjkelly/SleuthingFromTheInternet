require File.dirname(__FILE__) + '/environment.rb'

set :raise_errors, false
set :show_exceptions, false

configure :development do
  enable :logging, :dump_errors
  set :logging, Logger::DEBUG
  set :raise_errors, true
  set :database, 'sqlite:///db/development.db'
end

configure :production do
  db = URI.parse(ENV['SHARED_DATABASE_URL'] || 'postgres://localhost/mydb')

  ActiveRecord::Base.establish_connection(
    :adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
    :host     => db.host,
    :username => db.user,
    :password => db.password,
    :database => db.path[1..-1],
    :encoding => 'utf8'
  )
end

error do
  e = request.env['sinatra.error']
  puts e.to_s
  puts e.backtrace.join("\n")
  "Application Error!"
end

helpers do
  def link(url,text=url,opts={})
    attributes = ""
    opts.each { |key,value| attributes << key.to_s << "=\"" << value << "\" "}
    "<a href=\"#{url}\" #{attributes}>#{text}</a>"
  end
  
  def host
    request.env['HTTP_HOST']
  end
  
  def url(path = '')
    "#{scheme ||= 'http'}://#{host}#{path}"
  end
end

get '/' do
  @events = Events.find(:all, :order => "id desc", :limit => 5).reverse
  erb :index
end

get '/events.?:format?' do
  @events = Events.all
  if params[:format] and params[:format].downcase == 'json'
    content_type :json
    @events.to_json
  else    
    erb :events
  end
end

#get '/event/:id.?:format?' do
get %r{/event\/([^\/?#\.]+)(?:\.|%2E)?([^\/?#]+)?} do
  @event = Events.where("id = ?", params[:captures].first).first
  if params[:captures].second and params[:captures].second.downcase == 'json'
    content_type :json
    @event.to_json
  else
    erb :event
  end
end
