require 'rest-client'
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

    ['update_usgs', 'update_isc', 'update_fnet', 'update_kigam', 'update_retmc'].each do |source|
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

  wdcPage = Nokogiri::HTML(open('http://www.csndmc.ac.cn/index/main').read) do |config|
    config.strict.nonet
  end

  wdcPage.xpath('//table/tbody/tr[@class="eqdata"]/td/a').each { |row|
    hitPage = Nokogiri::HTML(open('http://www.csndmc.ac.cn' + row.attributes['href']).read) do |config|
      config.strict.nonet
    end
    # AddEvent(time, latitude, longitude, depth, mag, url, source)
    AddEvent(
      Time.parse(hitPage.xpath('//table[2]/tr/td').children[2].text + '+0800'),
      hitPage.xpath('//table[2]/tr/td').children[5].text,
      hitPage.xpath('//table[2]/tr/td').children[8].text,
      hitPage.xpath('//table[2]/tr/td').children[11].text,
      hitPage.xpath('//table[2]/tr/td').children[14].text,
      '#' + Digest::MD5.hexdigest(
        hitPage.xpath('//table[2]/tr/td').children[2].text +
        hitPage.xpath('//table[2]/tr/td').children[5].text +
        hitPage.xpath('//table[2]/tr/td').children[8].text +
        hitPage.xpath('//table[2]/tr/td').children[11].text +
        hitPage.xpath('//table[2]/tr/td').children[14].text
      ),
      'www.csndmc.ac.cn'
    )
  }
  puts "done."
end


task :update_usgs => :environment do
  print "Updating from USGS... "
  STDOUT.flush

  usgsEvents = JSON.parse(open("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson").read, :quirks_mode => true)

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

    iscEvents = Nokogiri::XML(open("http://irsc.ut.ac.ir/events_list.xml").read)

    iscEvents.xpath('//item').each do |iscEvent|
      AddEvent(Time.parse(iscEvent.xpath('date').text + ' UTC'),
               iscEvent.xpath('lat').text,
               iscEvent.xpath('long').text,
               iscEvent.xpath('dep').text,
               iscEvent.xpath('mag').text,
               '/newsview.php?&eventid=' + iscEvent.xpath('id').text + '&network=earth_ismc__',
               'irsc.ut.ac.ir')
    end

  puts "done."
end

task :update_fnet => :environment do
    print "Updating from NIED F-net... "
    STDOUT.flush

    form_data = {:sy => DateTime.now.year.to_s, :sm => DateTime.now.strftime('%m'), :init => '1', :page => '1', :one_page_view => '50', :time_sort => 'desc'}
    response = RestClient.post 'http://www.fnet.bosai.go.jp/event/sret.php?LANG=en', form_data
    fnetPage = Nokogiri::HTML(response.to_str) do |config|
        config.strict.nonet
    end

    fnetPage.xpath('//tr[@id]').each { |row|
      id = row.attributes['id'].value
      time = Time.parse(row.children[3].text + ' UTC')
      latitude = row.children[5].text
      longitude = row.children[7].text
      depth = row.children[11].text
      mag = row.children[13].text
      url = '/event/tdmt.php?LANG=en&_id=' + id

      AddEvent(time, latitude, longitude, depth, mag, url, 'www.fnet.bosai.go.jp')
    }

    puts "done."
end

task :update_kigam => :environment do
  print "Updating from KIGAM... "
  STDOUT.flush

  kigamPage = Nokogiri::HTML(open('http://quake.kigam.re.kr/earthquake/eqListUser.do?eq_gb=CDIDX00003&menu_nix=3Wlr1F77').read) do |config|
    config.strict.nonet
  end

  kigamPage.xpath("//table[contains(@class, 'tstyle_list mid')]/tbody/tr").each { |row|
    time = Time.strptime(row.children[1].text+'000000+0900', '%Y/%m/%d%H:%M:%S.%N%z')
    url = row.children[1].xpath('a/@href').to_s
    latitude = row.children[3].text
    longitude = row.children[5].text
    magnitude = row.children[7].text
    depth = row.children[9].text

    AddEvent(time, latitude, longitude, depth, magnitude, url, 'quake.kigam.re.kr')
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
