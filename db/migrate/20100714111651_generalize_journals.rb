class GeneralizeJournals < ActiveRecord::Migration
  def self.up
    change_table :journals do |t|
      t.rename :journalized_id, :versioned_id
      t.rename :created_on, :created_at

      t.integer :version, :default => 0, :null => false
      t.string :activity_type
      t.text :changes
      t.string :type

      t.index :versioned_id
      t.index :user_id
      t.index :activity_type
      t.index :created_at
      t.index :type
    end

    Journal.all.group_by(&:versioned_id).each_pair do |id, journals|
      journals.sort_by(:created_at).each_with_index do |j, idx|
        j.update_attribute(:type, "#{j.journalized_type}Journal")
        j.update_attribute(:version, idx + 1)
        # FIXME: Find some way to choose the right activity here
        j.update_attribute(:activity_type, j.journalized_type.constantize.activity_provider_options.keys.first)
      end
    end

    change_table :journals do |t|
      t.remove :journalized_type
    end

    JournalsDetails.all.each do |detail|
      journal = detail.journal
      journal.changes ||= {}
      journal.changes[detail.prop_key.to_sym] = [detail.old_value, detail.value]
      journal.save
    end

    drop_table :journal_details
  end

  def self.down
    create_table "journal_details", :force => true do |t|
      t.integer "journal_id",               :default => 0,  :null => false
      t.string  "property",   :limit => 30, :default => "", :null => false
      t.string  "prop_key",   :limit => 30, :default => "", :null => false
      t.string  "old_value"
      t.string  "value"
    end

    change_table "journals", :force => true do |t|
      t.rename :versioned_id, :journalized_id
      t.rename :created_at, :created_on

      t.string :journalized_type, :limit => 30, :default => "", :null => false
    end

    custom_field_names = CustomField.all.group_by(&:type)[IssueCustomField].collect(&:name)
    Journal.all.each do |j|
      j.update_attribute(:journalized_type, j.journalized.class.name)
      j.changes.each_pair do |prop_key, values|
        if Issue.columns.collect(&:name).include? prop_key.to_s
          property = :attr
        elsif CustomField.find_by_id(prop_key.to_s)
          property = :cf
        else
          property = :attachment
        end
        JournalDetail.create(:journal_id => j.id, :property => property,
          :prop_key => prop_key, :old_value => values.first, :value => values.last)
      end
    end

    change_table "journals", :force => true do |t|
      t.remove :type
      t.remove :version
      t.remove :activity_type
      t.remove :changes
    end

    add_index "journal_details", ["journal_id"], :name => "journal_details_journal_id"
    add_index "journals", ["created_on"], :name => "index_journals_on_created_on"
    add_index "journals", ["journalized_id", "journalized_type"], :name => "journals_journalized_id"
    add_index "journals", ["journalized_id"], :name => "index_journals_on_journalized_id"
    add_index "journals", ["user_id"], :name => "index_journals_on_user_id"
  end
end