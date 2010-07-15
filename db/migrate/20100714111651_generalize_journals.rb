class GeneralizeJournals < ActiveRecord::Migration
  def self.up
    drop_table :journals
    drop_table :journal_details
    create_table :journals do |t|
      t.belongs_to :versioned, :polymorphic => true
      t.belongs_to :user
      t.integer :version
      t.string :type
      t.text :notes
      t.text :changes
      t.timestamps
    end

    change_table :journals do |t|
      t.index [:versioned_id, :versioned_type]
      t.index [:user_id]
      t.index :type
      t.index :created_at
    end
  end

  def self.down
    drop_table :journals
    
    create_table "journal_details", :force => true do |t|
      t.integer "journal_id",               :default => 0,  :null => false
      t.string  "property",   :limit => 30, :default => "", :null => false
      t.string  "prop_key",   :limit => 30, :default => "", :null => false
      t.string  "old_value"
      t.string  "value"
    end
        
    create_table "journals", :force => true do |t|
      t.integer  "journalized_id",                 :default => 0,  :null => false
      t.string   "journalized_type", :limit => 30, :default => "", :null => false
      t.integer  "user_id",                        :default => 0,  :null => false
      t.text     "notes"
      t.datetime "created_on",                                     :null => false
    end
    
    add_index "journal_details", ["journal_id"], :name => "journal_details_journal_id"
    add_index "journals", ["created_on"], :name => "index_journals_on_created_on"
    add_index "journals", ["journalized_id", "journalized_type"], :name => "journals_journalized_id"
    add_index "journals", ["journalized_id"], :name => "index_journals_on_journalized_id"
    add_index "journals", ["user_id"], :name => "index_journals_on_user_id"
  end
end
