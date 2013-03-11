class CreateDurations < ActiveRecord::Migration
  def change
    create_table :durations do |t|
      t.integer :minutes
      t.integer :task_id
      t.integer :owner_id

      t.timestamps
    end
  end
end