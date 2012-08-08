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
    ['update_usgs', 'update_isc', 'update_fnet'].each do |source|
      Rake::Task[source].invoke
    end
    puts "Finished."
end

task :update_usgs => :environment do
  print "Updating from USGS... "
  STDOUT.flush

  usgsEvents = JSON.parse(open("http://earthquake.usgs.gov/earthquakes/feed/geojson/all/hour").read)

  usgsEvents['features'].each do |usgsEvent|
    AddEvent(usgsEvent['properties']['time'],
             usgsEvent['geometry']['coordinates'][1],
             usgsEvent['geometry']['coordinates'][0],
             usgsEvent['geometry']['coordinates'][2],
             usgsEvent['properties']['mag'],
             usgsEvent['properties']['url'],
             'earthquake.usgs.gov')
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
        time = Time.parse(row.children[2].text).to_i
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
        time = Time.parse(row.children[0].text).to_i
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

# Time should be UTC, seconds since epoch
def AddEvent(time, latitude, longitude, depth, mag, url, source)
    unless Events.exists?(:url => url) # URLs should be unique
        Events.create(:mag => mag,
                      :time => time,
                      :url => url,
                      :longitude => longitude,
                      :latitude => latitude,
                      :depth => depth,
                      :source => source,
                      :retrieved => Time.now.to_i)
    end 
end
