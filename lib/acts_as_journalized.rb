module Redmine
  module Acts
    module Journalized
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_journalized(options = {})
          return if self.included_modules.include?(Redmine::Acts::Journalized::InstanceMethods)

          send :include, Redmine::Acts::Journalized::InstanceMethods
          
          event_hash = {
            :description => :notes,
            :author => :user,
            :url => Proc.new do |o|
              {
                :controller => self.name.underscore,
                :action => 'show',
                :id => o.journalized_id,
                :anchor => "change-#{o.id}"
              }
            end
          }
          activity_hash = {
            :type => self.name.underscore.pluralize,
            :permission => "view_#{self.name.underscore.pluralize}".to_sym,
            :author_key => :user_id,
          }
          options.each_pair do |k, v|
            case
            when key = k.to_s.slice(/event_(.+)/, 1)
              event_hash[key.to_sym] = v
            when key = k.to_s.slice(/activity_(.+)/, 1)
              activity_hash[key.to_sym] = v
            end
          end
          
          Journal.acts_as_event event_hash
          Journal.acts_as_activity_provider activity_hash
        end
      end

      module InstanceMethods
        def self.included(base)
          base.extend ClassMethods
        end
        
        def init_journal(user, notes = "")
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
            (Issue.column_names - %w(id description lock_version created_on updated_on)).each {|c|
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
