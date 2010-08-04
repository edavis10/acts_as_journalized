class MergeWikiVersionsWithJournals < ActiveRecord::Migration
  def self.up

    WikiContent::Version.find_by_sql("SELECT * FROM wiki_content_versions").each do |wv|
      journal = WikiContentJournal.create!(:versioned_id => wv.wiki_content_id, :user_id => wv.author_id,
        :notes => wv.comments, :activity_type => "wiki_edits")
      journal.changes = {}
      journal.changes["compression"] = wv.compression
      journal.changes["data"] = wv.data
      journal.save
      journal.update_attribute(:version) = wv.version
    end
    drop_table :wiki_content_versions

    change_table :wiki_contents do
      t.rename :version, :lock_version
    end
  end

  def self.down
    change_table :wiki_contents do
      t.rename :lock_version, :version
    end

    create_table :wiki_content_versions do |t|
      t.column :wiki_content_id, :integer, :null => false
      t.column :page_id, :integer, :null => false
      t.column :author_id, :integer
      t.column :data, :binary
      t.column :compression, :string, :limit => 6, :default => ""
      t.column :comments, :string, :limit => 255, :default => ""
      t.column :updated_on, :datetime, :null => false
      t.column :version, :integer, :null => false
    end
    add_index :wiki_content_versions, :wiki_content_id, :name => :wiki_content_versions_wcid

    WikiContentJournal.all.each do |j|
      WikiContent::Version.create(:wiki_content_id => j.versioned_id, :page_id => j.versioned.page_id,
        :author_id => j.user_id, :data => j.changes["data"], :compression => j.changes["compression"],
        :comments => j.notes, :updated_on => j.created_at, :version => j.version)
    end

    WikiContentJournal.destroy_all
  end
end