# Loads Solid Queue's tables into the primary database, so this app only
# needs a single Postgres database (simpler on Heroku/Render for this MVP)
# rather than a separate physical "queue" database.
class LoadSolidQueueSchema < ActiveRecord::Migration[7.1]
  def up
    load(Rails.root.join("db/queue_schema.rb"))
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
