Dir[File.expand_path("../redmine/acts/journalized/*.rb", __FILE__)].each{|f| require f }

module Redmine
  module Acts
    module Journalized

      def self.included(base)
        base.extend ClassMethods
        base.extend Versioned
      end

      module ClassMethods
        def acts_as_journalized(options = {}, &block)
          return if versioned?

          send :include, Redmine::Acts::Journalized::InstanceMethods
          plural_name = self.name.underscore.pluralize

          event_hash = journalized_event_hash(plural_name, options)
          activity_hash = journalized_activity_hash(plural_name, options)

          journalized_merge_option_hashes(event_hash, activity_hash, options)

          self.acts_as_event event_hash
          self.acts_as_activity_provider activity_hash

          unless Redmine::Activity.providers[plural_name].include? self.name
            Redmine::Activity.register plural_name.to_sym
          end

          include Options
          include Changes
          include Creation
          include Users
          include Reversion
          include Reset
          include Conditions
          include Control
          include Tagging
          include Reload

          prepare_versioned_options(options)
          has_many :changes, options, &block
        end

        private
          def journalized_merge_option_hashes(event_hash, activity_hash, options)
            options.each_pair do |k, v|
              case
              when key = k.to_s.slice(/event_(.+)/, 1)
                event_hash[key.to_sym] = v
                options.delete(k)
              when key = k.to_s.slice(/activity_(.+)/, 1)
                activity_hash[key.to_sym] = v
                options.delete(k)
              end
            end
          end

          def journalized_activity_hash(plural_name, options)
            Hash.new.tap do |h|
              h[:type] = plural_name
              h[:author_key] = :user
              h[:find_options] = {
                :conditions => "#{options.delete(:activity_find_conditions)}" }

              if Redmine::AccessControl.permission(perm = "view_#{plural_name}".to_sym)
                h[:permission] = perm
              end
            end
          end

          def journalized_event_hash(plural_name, options)
            { :description => :notes,
              :author => Proc.new {|o| o.versions.last.user },
              :url => Proc.new do |o|
                { :controller => plural_name,
                  :action => 'show',
                  :id => o.id,
                  :anchor => "change-#{o.id}" }
              end }
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
