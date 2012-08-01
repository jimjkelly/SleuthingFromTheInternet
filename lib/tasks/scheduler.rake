require 'open-uri'
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
    events_handle = open("http://earthquake.usgs.gov/earthquakes/feed/geojson/all/hour")
    usgsEvents = JSON.parse(events_handle.read)

    usgsEvents['features'].each do |usgsEvent|
        unless Events.exists?(:event_id => usgsEvent['id'])
            Events.create(:event_id => usgsEvent['id'],
                          :mag => usgsEvent['properties']['mag'],
                          :place => usgsEvent['properties']['place'],
                          :time => usgsEvent['properties']['time'],
                          :tz => usgsEvent['properties']['tz'],
                          :url => usgsEvent['properties']['url'],
                          :felt => usgsEvent['properties']['felt'],
                          :cdi => usgsEvent['properties']['cdi'],
                          :mmi => usgsEvent['properties']['mmi'],
                          :alert => usgsEvent['properties']['alert'],
                          :status => usgsEvent['properties']['status'],
                          :tsunami => usgsEvent['properties']['tsunami'],
                          :sig => usgsEvent['properties']['sig'],
                          :net => usgsEvent['properties']['net'],
                          :code => usgsEvent['properties']['code'],
                          :ids => usgsEvent['properties']['ids'],
                          :sources => usgsEvent['properties']['sources'],
                          :types => usgsEvent['properties']['types'],
                          :longitude => usgsEvent['geometry']['coordinates'][0],
                          :latitude => usgsEvent['geometry']['coordinates'][1],
                          :depth => usgsEvent['geometry']['coordinates'][2],
                          :retrieved => Time.now.to_formatted_s(:rfc822))
        end
    end
    puts "done."
end