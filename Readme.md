Sleuthing From the Internet
===========================

Sleuthing from the Internet is a tool inspired by Jeffrey Lewis's post
(http://lewis.armscontrolwonk.com/archive/5534/my-own-sleuthing-from-home) on
the value of seismic data in detecting "Seismic Source Physics Experiments", or
in layman's terms: big booms.

The post discusses the challenges involved in using certain data sources that
can suddenly disappear.  This project seeks to aggregate relevant sources so
as to avoid this unfortunate set of circumstances, and provide automated
detection algorithms to alert interested parties of potential interesting
events.

Data Sources
============

Currently data is being culled from the USGS GEOJSON feed, and is scraped from
the Iranian Seismological Center and NIED's F-net recent events pages. The
frequency of data updates is currently every ten minutes.  (details can be found 
in the scraper at lib/tasks/scheduler.rake).

Note that while we make our data available for export via JSON feeds, especially
during this early in the development cycle data may disappear and the types of
data we store will likely change.  If you find certain types of current 
data useful, or would like to see other data sources or values, please create
and issue in the issue tracker (see below) so we can take this into consideration.

Bugs and Feature Requests
=========================

Please use the GitHub issue tracker for this project, found at
https://github.com/jimjkelly/SleuthingFromTheInternet/issues

Participating
=============

Participation from wonks and devs is welcome, either in guidance for features
or development work.  The canonical repository for the project is on GitHub at
https://github.com/jimjkelly/SleuthingFromTheInternet.

Development
-----------

Some quick notes on development.  To get your development environment set up,
assuming you already have ruby 1.9.x installed, you should just need to run
'bundle install' from this directory, and then run the command in the
Procfile to get the local server going.

You should run 'rake db:migrate' to get the database set up.

To create a migration (ie to change the database structure), run the following:

	rake db:create_migration NAME=EVENT_NAME

where EVENT_NAME is a descriptive name for the migration.  Note that it's
understood that this early in the development cycle that migrations may not be
practical, and the database may be blown out in favor of a new schema.  If
you are doing local development work, be cognizant of changes that may necessitate
this.

Run the server like so:

	bundle exec rackup config.ru -p 4567
	
or whatever port you would like.

License
=======

This work is issued in the public domain with no license nor any guarantee
as to its fitness for any particular task, including its stated purpose or the
purpose of picking up women in DC bars.
