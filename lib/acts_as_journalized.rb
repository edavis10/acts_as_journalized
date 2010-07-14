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

          include SaveHooks
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

          plural_name = self.name.underscore.pluralize

          event_hash = journalized_event_hash(plural_name, options)
          activity_hash = journalized_activity_hash(plural_name, options)
          journalized_merge_option_hashes(event_hash, activity_hash, options)

          acts_as_event event_hash
          acts_as_activity_provider activity_hash

          unless Redmine::Activity.providers[plural_name].include? self.name
            Redmine::Activity.register plural_name.to_sym
          end

          prepare_versioned_options(options)
          has_many :journals, options, &block
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
            {}.tap do |h|
              h[:type] = plural_name
              h[:author_key] = :user_id
              h[:find_options] = {
                :conditions => "#{options.delete(:activity_find_conditions)}" }

              if Redmine::AccessControl.permission(perm = "view_#{plural_name}".to_sym)
                h[:permission] = perm
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
              end }
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
        def init_journal(notes = "")
          @notes ||= ""
          if self.respond_to? :custom_values
            @custom_values_before_change = custom_values.inject({}) do |hash, cv|
              hash[cv.custom_field_id] = cv.value
              hash
            end
          end
          @current_journal = current_journal
        end

        # Saves the notes and custom value changes in the last Journal
        # Called after_update
        def update_journal
          if @custom_values_before_change
            # Has custom values from init_journal_notes
            changed_custom_values = custom_values.inject({}) do |hash, c|
              unless (@custom_values_before_change[c.custom_field_id] == c.value ||
                  @custom_values_before_change[c.custom_field_id].blank? && c.value.blank?)
                hash[c.custom_field_id.to_s] = [@custom_values_before_change[c.custom_field_id], c.value]
              end
              hash
            end
          end

          unless changed_custom_values.empty? && @notes.empty?
            unless current_journal == @current_journal
              # No attribute changes, update the timestamp to include notes and changed
              # custom values
              updated_on_will_change!
              save
              @current_journal = current_journal
            end
            @current_journal.notes = @notes
            @current_journal.details.merge(changed_custom_values)
            @current_journal.save
          end
        end

        module ClassMethods
        end
      end
    end
  end
end
