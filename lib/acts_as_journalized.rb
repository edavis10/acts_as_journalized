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

          include Options
          include Changes
          include Creation
          include Users
          include Reversion
          include Reset
          include Conditions
          include Control
          include Reload
          include Permissions
          include SaveHooks

          plural_name = self.name.underscore.pluralize

          event_hash = journalized_event_hash(plural_name, options)
          activity_hash = journalized_activity_hash(plural_name, options)

          acts_as_event event_hash
          acts_as_activity_provider activity_hash

          unless Redmine::Activity.providers[plural_name].include? self.name
            Redmine::Activity.register plural_name.to_sym
          end

          prepare_versioned_options(options)
          has_many :journals, options, &block
        end

        private
          def journalized_option_hashes(prefix, options)
            returning({}) do |hash|
              options.each_pair do |k, v|
                if key = k.to_s.slice(/#{prefix}_(.+)/, 1)
                  hash[key.to_sym] = v
                  options.delete(k)
                end
              end
            end
          end

          def journalized_activity_hash(plural_name, options)
            journalized_option_hashes("activity", options).tap do |h|
              h[:type] ||= plural_name
              h[:author_key] = :user_id
              h[:timestamp] = "#{Journal.table_name}.created_at"
              h[:find_options] = {
                :conditions => "#{h[:activity_find_conditions]} AND
                                #{Journal.table_name}.journalized_type == #{name} AND
                                #{Journal.table_name}.type == #{h[:type]}" }

              if Redmine::AccessControl.permission(perm = :"view_#{plural_name}")
                # Needs to be like this, since setting the key to nil would mean
                # everyone may see this activity
                h[:permission] ||= perm
              end
            end
          end

          def journalized_event_hash(plural_name, options)
            { :description => :notes,
              :author => Proc.new {|o| o.journals.last.user },
              :url => Proc.new do |o|
                { :controller => plural_name,
                  :action => 'show',
                  :id => o.id,
                  :anchor => "change-#{o.id}" }
              end }.reverse_merge journalized_option_hashes("event", options)
          end
      end

      module SaveHooks
        def self.included(base)
          base.extend ClassMethods

          base.class_eval do
            before_save :init_journal
            after_save :update_journal
          end
        end

        # Saves the current custom values, notes and journal to include them in the next version
        # Called before save
        def init_journal(user = User.current, notes = "")
          @notes ||= notes
          @journal_user ||= User.current
          if self.respond_to? :custom_values
            @custom_values_before_save = custom_values.inject({}) do |hash, cv|
              hash[cv.custom_field_id] = cv.value
              hash
            end
          end
          @current_journal = current_journal
        end

        # Saves the notes and custom value changes in the last Journal
        # Called after_update
        def update_journal
          unless current_journal == @current_journal
            (current_journal.tap {|j| j.user = @journal_user }).save!
          end

          if @custom_values_before_save
            # Has custom values from init_journal_notes
            changed_custom_values = current_custom_values - @custom_values_before_save
          end

          unless changed_custom_values.empty? && @notes.empty?
            update_extended_journal_contents(changed_custom_values)
          end
          @current_journal = @journal_user = @notes = nil
        end

        # Saves the notes and changed custom values to the journal
        # Creates a new journal, if no immediate attributes were changed
        def update_extended_journal_contents(changed_custom_values)
          if current_journal == @current_journal
            # No attribute changes, create a new journal entry
            # on which notes and changed custom values will be written
            create_version
          end
          current_journal.tap do |j|
            j.notes = @notes
            j.details.merge!(changed_custom_values)
            j.user = @journal_user
          end.save!
        end

        # Allow to semantically substract a hash of custom value changes from another
        def current_custom_values
          cvs = custom_values
          class << cvs
            def - cvs_before_save
              self.inject({}) do |hash, c|
                unless cvs_before_save[c.custom_field_id] == c.value
                  hash[c.custom_field_id] = [cvs_before_save[c.custom_field_id], c.value]
                end
                hash
              end
            end
          end
          cvs
        end

        module ClassMethods
        end
      end
    end
  end
end
