require 'open-uri'
require 'nokogiri'
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

    ['update_usgs', 'update_isc', 'update_fnet', 'update_kigam'].each do |source|
        begin
            Rake::Task[source].invoke
        rescue
            $stderr.puts(' Unable to run ' + source + ' due to unknown problem.')
            p $!
            puts $@
        end
    end
    puts "Finished."
end

task :update_usgs => :environment do
  print "Updating from USGS... "
  STDOUT.flush

  usgsEvents = JSON.parse(open("http://earthquake.usgs.gov/earthquakes/feed/geojson/all/hour").read)

  usgsEvents['features'].each do |usgsEvent|
    # Note that we limit our epoch time to 10 characters, for some reason
    # USGS pads an extra 3 zeros at the end and it messes things up.
    AddEvent(Time.at(usgsEvent['properties']['time'][0...10].to_i).utc,
             usgsEvent['geometry']['coordinates'][1],
             usgsEvent['geometry']['coordinates'][0],
             usgsEvent['geometry']['coordinates'][2],
             usgsEvent['properties']['mag'],
             usgsEvent['properties']['url'].gsub('http://earthquake.usgs.gov', ''),
             'earthquake.usgs.gov')
    # Note that we removed the server name there because we take the source and prepend it
    # at display time
  end
  puts " done."
end

task :update_isc => :environment do
    print "Updating from the Iranian Seismological Center..."
    STDOUT.flush
    
    iscPage = Nokogiri::HTML(open('http://irsc.ut.ac.ir/currentearthq.php').read) do |config|
        config.strict.nonet
    end
      
    iscPage.xpath('//tr[starts-with(@class, "DataRow")]').each { |row|
        time = Time.parse(row.children[2].text + ' UTC')
        latitude = row.children[4].text
        longitude = row.children[6].text
        
        depth = row.children[8].text
        mag = row.children[10].text
        url = row.at_xpath('.//td/span[@dir="ltr"]/a')['href']
        unless url.starts_with?('/')
            url = '/' + url
        end
        
        AddEvent(time, latitude, longitude, depth, mag, url, 'irsc.ut.ac.ir')
    }
  
  puts " done."
end

task :update_fnet => :environment do
    print "Updating from NIED F-net..."
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
    
    puts " done."
end

task :update_kigam => :environment do
  print "Updating from KIGAM..."
  STDOUT.flush

  kigamPage = Nokogiri::HTML(open('http://quake.kigam.re.kr/pds/db/list.html').read) do |config|
    config.strict.nonet
  end

  #kigamPage.xpath("//a[starts-with(@href, 'read_ok.php')]").each { |row|
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
      puts 'OMG TIME: ' + kigamEventsData[1].text.strip
      time = Time.parse(kigamEventsData[0].text.strip + ' ' + kigamEventsData[1].text.strip.gsub('\..*', '') + ' UTC')
      latitude = kigamEventsData[2].text.strip
      longitude = kigamEventsData[3].text.strip
      magnitude = kigamEventsData[4].text.strip
      depth = kigamEventsData[5].text.strip
      
      AddEvent(time, latitude, longitude, depth, magnitude, url, 'quake.kigam.re.kr')
    end
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
    
    latitude = latitude.to_s.gsub(/[^0-9.\-]/, '')
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
    end 
end
