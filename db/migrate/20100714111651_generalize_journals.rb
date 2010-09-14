class GeneralizeJournals < ActiveRecord::Migration
  def self.up
    # This is provided here for migrating up after the JournalDetails has been removed
    unless Object.const_defined?("JournalDetails")
      Object.const_set("JournalDetails", Class.new(ActiveRecord::Base))
    end

    change_table :journals do |t|
      t.rename :journalized_id, :journaled_id
      t.rename :created_on, :created_at

      t.integer :version, :default => 0, :null => false
      t.string :activity_type
      t.text :changes
      t.string :type

      t.remove_index "created_on"
      t.remove_index "journalized_id"

      t.index :journaled_id
      t.index :activity_type
      t.index :created_at
      t.index :type
    end

    Journal.all.group_by(&:journaled_id).each_pair do |id, journals|
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

    JournalDetails.all.each do |detail|
      journal = Journal.find(detail.journal_id)
      changes = journal.changes || {}
      changes[detail.prop_key.to_sym] = [detail.old_value, detail.value]
      journal.update_attribute(:changes, changes.to_yaml)
    end

    # Create creation journals for all activity providers
    providers = Redmine::Activity.providers.collect {|k, v| v.collect(&:constantize) }.flatten.compact.uniq
    providers.each do |p|
      p.find(:all).each do |o|
        unless o.last_journal
          o.send(:update_journal)
          created_at = nil
          [:created_at, :created_on, :updated_at, :updated_on].each do |m|
            if o.respond_to? m
              created_at = o.send(m)
              break
            end
          end
          p "Updateing #{o}"
          o.last_journal.update_attribute(:created_at, created_at) if created_at
        end
      end
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
      t.rename :journaled_id, :journalized_id
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
      t.remove_index :journaled_id
      t.remove_index :activity_type
      t.remove_index :created_at
      t.remove_index :type

      t.remove :type
      t.remove :version
      t.remove :activity_type
      t.remove :changes
    end

    add_index "journal_details", ["journal_id"], :name => "journal_details_journal_id"
    add_index "journals", ["created_on"], :name => "index_journals_on_created_on"
    add_index "journals", ["journalized_id", "journalized_type"], :name => "journals_journalized_id"
    add_index "journals", ["journalized_id"], :name => "index_journals_on_journalized_id"
  end
end
