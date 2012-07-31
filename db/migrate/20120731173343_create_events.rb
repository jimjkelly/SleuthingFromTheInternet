class CreateEvents < ActiveRecord::Migration
  def up
    create_table :events do |t|
      t.string    :event_id
      t.float     :mag
      t.string    :place
      t.integer   :time
      t.integer   :tz
      t.string    :url
      t.integer   :felt
      t.integer   :cdi
      t.string    :mmi
      t.string    :alert
      t.string    :status
      t.string    :tsunami
      t.string    :sig
      t.string    :net
      t.string    :code
      t.string    :ids
      t.string    :sources
      t.string    :types
      t.float     :latitude
      t.float     :longitude
      t.float     :depth
      t.datetime  :retrieved
    end
  end

  def down
    drop_table :events
  end
end
