class CreateEvents < ActiveRecord::Migration
  def up
    create_table :events do |t|
      t.string    :mag
      t.datetime  :time
      t.string    :url
      t.string    :source
      t.string    :latitude
      t.string    :longitude
      t.string    :depth
      t.datetime  :retrieved
    end
  end

  def down
    drop_table :events
  end
end
