require File.dirname(__FILE__) + '/environment.rb'

set :raise_errors, false
set :show_exceptions, false

GENERIC_ERROR = 'An error encountered.  Please try again later or open a ticket on <a href="https://github.com/jimjkelly/SleuthingFromTheInternet/issues">GitHub</a>, and reference this code: '

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

  def error(location='UNKNOWN', text=GENERIC_ERROR)
    # A semi-random code to allow us to correlate
    # dumped logs to error reporting, should a user
    # pass along the code
    code = SecureRandom.hex(4)
    puts "Exception in " + location + ", error code: " + code + "\n"

    return text + "(" + location + ": " + code + ")"
  end
end

get '/' do
  erb :index
end


get '/events.?:format?' do
  if params[:limit]
    limit = params[:limit]
  else
    limit = 100
  end
  
  @events = Events.order(id: :desc).limit(limit)

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
  puts @event.time
  if params[:captures].second and params[:captures].second.downcase == 'json'
    content_type :json
    @event.to_json
  else
    erb :event
  end
end

post '/subscribe' do
  begin
    sent_values = {:email => params[:email],
      :mindepth => params[:mindepth],
      :maxdepth => params[:maxdepth],
      :minmag => params[:minmag],
      :maxmag => params[:maxmag],
      :mindev => params[:mindev],
      :maxdev => params[:maxdev],
      :source => params[:source],
      :digest => params[:digest] == 'true' ? true : false
    }

    if Subscribers.exists?(:email => params[:email])
      Subscribers.update(Subscribers.find(:first, :conditions => ['email = ?', params[:email]]),
                         sent_values)
      'SUBSCRIPTION UPDATED'
    else
      Subscribers.create(sent_values)
      ses = AWS::SES::Base.new(
        :access_key_id  => ENV['S3_KEY'],
        :secret_access_key => ENV['S3_SECRET']
      )

      body = 'You are now subscribed to receive emails about events that match your selection criteria.  You can change those criteria on the site in the same way you just signed up.  Set selection criteria on the main page, then click the subscription envelope.

'
      body += 'If you would like to unsubscribe, simply click the following link: http://sleuthingfromtheinternet.com/unsubscribe/' + params[:email]

      ses.send_email(
        :to => params[:email], 
        :from => 'Sleuthing From the Internet <do-not-reply@sleuthingfromtheinternet.com>', 
        :subject => 'Subscription for Sleuthing From the Internet',
        :body => body
      )

      'SUBSCRIPTION ADDED'
    end
  rescue => e
    puts e.to_s
    puts e.backtrace.join("\n")
    error('SUBSCRIBE')
  end
end

get '/unsubscribe/:email' do
  begin
    if Subscribers.exists?(:email => params[:email])
      Subscribers.destroy_all(:email => params[:email])
      erb :index, :locals => { :alert => 'Your unsubscription request has been processed, and you will recieve no further email communications from us to ' + params[:email] + '.' }
    else
      erb :index, :locals => { :alert => 'We\'re sorry, but we cannot find a record of ' + params[:email] + ' being subscribed.  If you think this is an error, please open an issue on <a href="https://github.com/jimjkelly/SleuthingFromTheInternet/issues">GitHub</a> and we will look into it as soon as possible.'}
    end
  rescue => e
    puts e.to_s
    puts e.backtrace.join("\n")
    error('UNSUBSCRIBE')
  end
end
