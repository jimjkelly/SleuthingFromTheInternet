class CreateSubscribers < ActiveRecord::Migration
  def up
    create_table :subscribers do |t|
      t.string    :email
      t.string    :depth
      t.string    :mag
      t.string    :time_deviation
      t.string    :source
      t.boolean   :digest
    end
  end

  def down
    drop_table :subscribers
  end
end
