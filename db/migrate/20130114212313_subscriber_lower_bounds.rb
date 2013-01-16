class SubscriberLowerBounds < ActiveRecord::Migration
  def change
    change_table :subscribers do |t|
        t.string :mindepth
        t.rename :depth, :maxdepth
        t.string :minmag
        t.rename :mag, :maxmag
        t.string :mindev
        t.rename :time_deviation, :maxdev
    end
  end
end
