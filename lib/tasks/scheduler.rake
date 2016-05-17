require 'digest/md5'
require 'open-uri'
require 'nokogiri'
require 'aws/ses'
require 'json'

# Set a placeholder RACK_ENV for when this is run outside the scope of rack 
ENV['RACK_ENV'] = 'PLACEHOLDER' if not ENV.key?('RACK_ENV')

task :environment do
    require File.dirname(__FILE__) + '/../../environment.rb'
end


=begin

An example event from usgs:

{"type"=>"Feature",
 "properties"=>
  {"mag"=>2.1,
   "place"=>"12km SE of Laytonville, California",
   "time"=>1343763602,
   "tz"=>-420,
   "url"=>"/earthquakes/eventpage/nc71824836",
   "felt"=>nil,
   "cdi"=>nil,
   "mmi"=>nil,
   "alert"=>nil,
   "status"=>"AUTOMATIC",
   "tsunami"=>nil,
   "sig"=>"68",
   "net"=>"nc",
   "code"=>"71824836",
   "ids"=>",nc71824836,",
   "sources"=>",nc,",
   "types"=>
    ",general-link,general-link,geoserve,nearby-cities,origin,scitech-link,"},
 "geometry"=>{"type"=>"Point", "coordinates"=>[-123.4017, 39.595, 10.6]},
 "id"=>"nc71824836"}

You can also refer to the model format, which is largely the aboved flattened,
in db/models.rb or more specifically the migrations in db/migrations

=end

desc "This task is called by the Heroku scheduler add-on to update Events"
task :update_events => :environment do
    puts "Updating events..."

    if Events.last
      initialIndex = Events.last.id
    else
      initialIndex = -1
    end
    
    ['update_usgs', 'update_isc', 'update_fnet', 'update_kigam', 'update_wdc', 'update_retmc'].each do |source|
        begin
            Rake::Task[source].invoke
        rescue
            puts ""
            $stderr.puts(' Error: Unable to run ' + source + ' due to unknown problem.')
            p $!
            puts $@
        end
    end

    update_subscribers(initialIndex)

    puts "Finished."
end

task :update_retmc => :environment do
  print "Updating from RETMC... "
  STDOUT.flush

  retmcPage = Nokogiri::XML(open('http://www.koeri.boun.edu.tr/sismo/zeqmap/xmle/son24saat.xml').read) do |config|
    config.strict.nonet
  end

  retmcPage.xpath('//earhquake').each do |row|
    AddEvent(
      Time.parse(row.attributes['name'].value + ' UTC'),
      row.attributes['lat'].value,
      row.attributes['lng'].value,
      row.attributes['Depth'].value,
      row.attributes['mag'].value,
      '/sismo/2/latest-earthquakes/list-of-latest-events/#' + Digest::MD5.hexdigest(
        row.attributes['name'].value +
        row.attributes['lat'].value +
        row.attributes['lng'].value +
        row.attributes['Depth'].value +
        row.attributes['mag'].value
      ),
      'www.koeri.boun.edu.tr'
    )
  end
  puts "done."
end

task :update_wdc => :environment do
  print "Updating from WDC... "
  STDOUT.flush

  wdcPage = Nokogiri::HTML(open('http://www.csndmc.ac.cn/wdc4seis/').read) do |config|
    config.strict.nonet
  end

  wdcPage.xpath('//table/tr/td/span/table/tr').each { |row|
    AddEvent(
      Time.parse(row.children[1].text + '+0800'),
      row.children[3].text,
      row.children[5].text,
      row.children[7].text,
      row.children[9].text,
      '/wdc4seis/#' + Digest::MD5.hexdigest(
        row.children[1].text +
        row.children[3].text +
        row.children[5].text +
        row.children[7].text +
        row.children[9].text
      ),
      'www.csndmc.ac.cn'
    )
  }
  puts "done."
end


task :update_usgs => :environment do
  print "Updating from USGS... "
  STDOUT.flush

  usgsEvents = JSON.parse(open("http://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson").read, :quirks_mode => true)

  usgsEvents['features'].each do |usgsEvent|
    AddEvent(Time.at(usgsEvent['properties']['time']/1000).utc,
             usgsEvent['geometry']['coordinates'][1],
             usgsEvent['geometry']['coordinates'][0],
             usgsEvent['geometry']['coordinates'][2],
             usgsEvent['properties']['mag'],
             usgsEvent['properties']['url'].gsub('http://earthquake.usgs.gov', ''),
             'earthquake.usgs.gov')
    # Note that we removed the server name there because we take the source and prepend it
    # at display time
  end
  puts "done."
end

task :update_isc => :environment do
    print "Updating from the Iranian Seismological Center... "
    STDOUT.flush

    iscEvents = JSON.parse(open("http://irsc.ut.ac.ir/json_currentearthq.php").read)
    
    iscEvents['item'].each do |iscEvent|
      AddEvent(Time.parse(iscEvent['date'] + ' UTC'), 
               iscEvent['lat'],
               iscEvent['long'],
               iscEvent['dep'],
               iscEvent['mag'],
               '/newsview.php?&eventid=' + iscEvent['id'] + '&network=earth_ismc__',
               'irsc.ut.ac.ir')
    end
  
  puts "done."
end

task :update_fnet => :environment do
    print "Updating from NIED F-net... "
    STDOUT.flush
    
    fnetPage = Nokogiri::HTML(open('http://www.fnet.bosai.go.jp/event/joho.php?LANG=en').read) do |config|
        config.strict.nonet
    end
    
    fnetPage.xpath('//tr[@class="joho_bg3"]').each { |row|
        time = Time.parse(row.children[0].text + ' UTC')
        latitude = row.children[1].text
        longitude = row.children[2].text
        depth = row.children[3].text
        mag = row.children[4].text
        url = row.at_xpath('.//a')['href']
        if url.starts_with?('.')
            url = '/event' + url[1..-1]
        end
        
        AddEvent(time, latitude, longitude, depth, mag, url, 'www.fnet.bosai.go.jp')
    }
    
    puts "done."
end

task :update_kigam => :environment do
  print "Updating from KIGAM... "
  STDOUT.flush

  kigamPage = Nokogiri::HTML(open('http://quake.kigam.re.kr/pds/db/list.html').read) do |config|
    config.strict.nonet
  end

  kigamPage.xpath("//a[starts-with(@href, 'read_ok.php')]").to_a.map { |i| i['href'] }.uniq.each { |url|
    url = '/pds/db/' + url

    # Because we need to make a second call to get more data, we check
    # to see if we've seen this or not first
    unless Events.exists?(:url => url)
      kigamRedirectPage = Nokogiri::HTML(open('http://quake.kigam.re.kr' + url).read) do |config|
        config.strict.nonet
      end

      kigamRedirectedURL = kigamRedirectPage.at_xpath('//script').to_s.gsub("<script>document.location.replace('", '').gsub("');</script>", "")

      kigamEventPage = Nokogiri::HTML(open('http://quake.kigam.re.kr/pds/db/' + kigamRedirectedURL).read) do |config|
        config.strict.nonet
      end
      kigamEventsData = kigamEventPage.xpath("//td[@bgcolor='#F0F0F0']").children
      time = Time.parse(kigamEventsData[0].text.strip + ' ' + kigamEventsData[1].text.strip.gsub('\..*', '') + ' UTC')
      latitude = kigamEventsData[2].text.strip
      longitude = kigamEventsData[3].text.strip
      magnitude = kigamEventsData[4].text.strip
      depth = kigamEventsData[5].text.strip
      
      AddEvent(time, latitude, longitude, depth, magnitude, url, 'quake.kigam.re.kr')
    end
  }
  puts "done."
end  

# This will look at every event we find after initial_id, and then look at people's
# subscription settings, and email them information about new events.
def update_subscribers(initial_id)
  notifications = Hash.new

  # Check our new events to see who should be notified about what
  Events.where(["id > (?)", initial_id]).all.each { |event|    
    if((60 - event.time.min) < event.time.min)
      deviation = 60 - event.time.min
    else
      deviation = event.time.min
    end

    Subscribers.all.each { |subscriber|
      notify = true
      if ((subscriber.mindepth.to_f > event.depth.to_f) || (event.depth.to_f > subscriber.maxdepth.to_f))
        notify = false
      elsif ((subscriber.minmag.to_f > event.mag.to_f) || (event.mag.to_f > subscriber.maxmag.to_f))
        notify = false
      elsif ((subscriber.mindev.to_f > deviation) || (deviation > subscriber.maxdev.to_f))
        notify = false
      elsif ((subscriber.source != 'All Sources') && (subscriber.source != event.source))
        notify = false
      end

      if notify
        if (!notifications[subscriber])
          notifications[subscriber] = Array.new
        end

        notifications[subscriber] << event
      end
    }
  }

  ses = AWS::SES::Base.new(
    :access_key_id  => ENV['S3_KEY'],
    :secret_access_key => ENV['S3_SECRET']
  )

  notifications.each_key { |subscriber|
    body = 'We have new events matching your criteria:

'

    notifications[subscriber].each { |event|
      body += '    Time: ' + event.time.to_s + '
'
      body += '    Magnitude: ' + event.mag.to_s + '
'
      body += '    Depth: ' + event.depth.to_s + ' km
'
      body += '    Latitude/Longitude: ' + event.latitude.to_s + '/' + event.longitude.to_s + '
'
      body += '    Source: ' + event.source + '
'
      body += '    Link: http://sleuthingfromtheinternet.com/event/' + event.id.to_s + '

'
    }

    if subscriber.digest
      body += 'NOTE: We recognize you requested to receive digest emails, but digest functionality is currently not working.  We will work to fix this as soon as possible and apologize for any inconvenience this causes you.

'
    end

    body += 'You can change your match criteria by going to http://sleuthingfromtheinternet.com again, and going through the same process you did to sign up.  Note that if you are receiving a lot of events from us, restricting the match criteria can be helpful.

'

    body += 'In the event you no longer wish to receive communications from us, you can unsubscribe here: http://sleuthingfromtheinternet.com/unsubscribe/' + subscriber.email + '

'

    ses.send_email(
      :to => subscriber.email, 
      :from => 'Sleuthing From the Internet <do-not-reply@sleuthingfromtheinternet.com>', 
      :subject => 'New Events from Sleuthing From the Internet',
      :body => body
    )
  }
end

# Time should be a Time utc object
def AddEvent(time, latitude, longitude, depth, mag, url, source)
    # First do some normalization:
    mag = mag.to_s.gsub(/[^0-9.]/, '')
    
    if depth.to_s.include? "shallow"
        depth = "0"
    else
        depth = depth.to_s.gsub(/[^0-9.]/, '')
    end

    if latitude.to_s.include? 'S'
      latitude = "-" + latitude
    end
    latitude = latitude.to_s.gsub(/[^0-9.\-]/, '')

    if longitude.to_s.include? 'W'
      longitude = "-" + longitude
    end
    longitude = longitude.to_s.gsub(/[^0-9.\-]/, '')

      unless Events.exists?(:url => url) # URLs should be unique
        Events.create(:mag => mag,
                      :time => time,
                      :url => url,
                      :longitude => longitude,
                      :latitude => latitude,
                      :depth => depth,
                      :source => source,
                      :retrieved => Time.now.utc)

        if time.nil? || latitude.empty? || longitude.empty? || depth.empty? || mag.empty? || url.empty?
          puts "Error collecting all information for " + source + url
        end
    end
end
