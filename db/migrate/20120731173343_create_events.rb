class CreateEvents < ActiveRecord::Migration
  def up
    create_table :events do |t|
      t.float     :mag
      t.integer   :time
      t.string    :url
      t.string    :source
      t.float     :latitude
      t.float     :longitude
      t.float     :depth
      t.integer   :retrieved
    end
  end

  def down
    drop_table :events
  end
end
