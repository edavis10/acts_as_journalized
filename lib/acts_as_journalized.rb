module Redmine
  module Acts
    module Journalized
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_journalized(options = {})
          return if self.included_modules.include?(Redmine::Acts::Journalized::InstanceMethods)
          options.delete(:activity_find_options)
          options.delete(:activity_author_key)
          options.delete(:event_author)
          send :include, Redmine::Acts::Journalized::InstanceMethods
          plural_name = self.name.underscore.pluralize
          
          event_hash = {
            :description => :notes,
            :author => Proc.new {|o| User.find_by_id(o.journal_user_id)},
            :url => Proc.new do |o|
              {
                :controller => plural_name,
                :action => 'show',
                :id => o.id,
                :anchor => "change-#{o.id}"
              }
            end
          }
          activity_hash = {
            :type => plural_name,
            :author_key => :journal_user_id,
            :find_options => {
              :select => "*, #{self.table_name}.id AS id, #{Journal.table_name}.notes AS notes, #{Journal.table_name}.user_id AS journal_user_id",
              :conditions => options.delete(:activity_find_conditions) || "",
              :joins => [
                "LEFT OUTER JOIN #{Journal.table_name}
                  ON #{Journal.table_name}.journalized_id = #{self.table_name}.id",
                "LEFT OUTER JOIN #{JournalDetail.table_name}
                  ON  #{JournalDetail.table_name}.journal_id = #{Journal.table_name}.id",
                "LEFT OUTER JOIN #{Project.table_name} 
                  ON  #{Project.table_name}.id = 
                  #{self.table_name}.#{options[:project_key] || 'project_id'}"]}}

          if Redmine::AccessControl.permission(perm = "view_#{plural_name}".to_sym)
            activity_hash[:permission] = perm
          end

          options.each_pair do |k, v|
            case
            when key = k.to_s.slice(/event_(.+)/, 1)
              event_hash[key.to_sym] = v
            when key = k.to_s.slice(/activity_(.+)/, 1)
              activity_hash[key.to_sym] = v              
            end
          end

          self.acts_as_event event_hash
          self.acts_as_activity_provider activity_hash

          unless Redmine::Activity.providers[plural_name].include? self.name
            Redmine::Activity.register plural_name.to_sym
          end
        end
      end

      module InstanceMethods
        def self.included(base)
          base.extend ClassMethods
          
          base.class_eval do
            after_save :create_journal
          end
        end
        
        def init_journal(user, notes = "")
          @notes ||= ""
          @current_journal ||= Journal.new(:journalized => self, :user => user, :notes => notes)
          @object_before_change = self.clone
          @object_before_change.status = self.status
          if self.respond_to? :custom_values
            @custom_values_before_change = {}
            self.custom_values.each {|c| @custom_values_before_change[c.custom_field_id] = c.value }
          end
          # Make sure updated_on is updated when adding a note.
          updated_on_will_change!
          @current_journal
        end
        
        # Saves the changes in a Journal
        # Called after_save
        def create_journal
          if @current_journal
            # attributes changes
            (self.class.column_names - %w(id description lock_version created_on updated_on)).each {|c|
              @current_journal.details << JournalDetail.new(:property => 'attr',
              :prop_key => c,
              :old_value => @object_before_change.send(c),
              :value => send(c)) unless send(c)==@object_before_change.send(c)
            }
            if self.respond_to? :custom_values
              # custom fields changes
              custom_values.each {|c|
                next if (@custom_values_before_change[c.custom_field_id]==c.value ||
                (@custom_values_before_change[c.custom_field_id].blank? && c.value.blank?))
                @current_journal.details << JournalDetail.new(:property => 'cf', 
                :prop_key => c.custom_field_id,
                :old_value => @custom_values_before_change[c.custom_field_id],
                :value => c.value)
              }
            end
            @current_journal.save
          end
        end
        
        module ClassMethods
        end
      end
    end
  end
end
