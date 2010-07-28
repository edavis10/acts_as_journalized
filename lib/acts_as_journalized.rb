Dir[File.expand_path("../redmine/acts/journalized/*.rb", __FILE__)].each{|f| require f }
require_dependency 'lib/ar_condition'

module Redmine
  module Acts
    module Journalized

      def self.included(base)
        base.extend ClassMethods
        base.extend Versioned
      end

      module ClassMethods

        def plural_name
          self.name.underscore.pluralize
        end

        # A model might provide as many activity_types as it wishes.
        # Activities are just different search options for the event a model provides
        def acts_as_activity(options = {})
          activity_hash = journalized_activity_hash(options)
          type = activity_hash[:type]
          acts_as_activity_provider activity_hash
          unless Redmine::Activity.providers[type].include? self.name
            Redmine::Activity.register type.to_sym, :class_name => self.name
          end
        end

        # This call will add an activity and, if neccessary, start the versioning and
        # add an event callback on the model.
        # Versioning and acting as an Event may only be applied once.
        # To apply more than on activity, use acts_as_activity
        def acts_as_journalized(options = {}, &block)
          activity_hash, event_hash, version_hash = split_option_hashes(options)

          acts_as_activity(activity_hash)

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

          journal_class.acts_as_event journalized_event_hash(event_hash)

          prepare_versioned_options(version_hash)
          has_many :journals, version_hash.merge({:class_name => journal_class.name,
                :foreign_key => "versioned_id" }), &block
        end

        def journal_class
          journal_class_name = "#{name.gsub("::", "_")}Journal"
          if Object.const_defined?(journal_class_name)
            Object.const_get(journal_class_name)
          else
            Object.const_set(journal_class_name, Class.new(Journal)).tap do |c|
              # Run after the inherited hook to associate with the parent record.
              c.class_eval("belongs_to :versioned, :class_name => '#{name}'")
            end
          end
        end

        private
          # Splits an option has into three hashes:
          ## => [{ options prefixed with "activity_" }, { options prefixed with "event_" }, { other options }]
          def split_option_hashes(options)
            activity_hash = {}
            event_hash = {}
            version_hash = {}

            options.each_pair do |k, v|
              case
              when k.to_s =~ /^activity_(.+)$/
                activity_hash[$1.to_sym] = v
              when k.to_s =~ /^event_(.+)$/
                event_hash[$1.to_sym] = v
              else
                version_hash[k.to_sym] = v
              end
            end
            [activity_hash, event_hash, version_hash]
          end

          # Merges the passed activity_hash with the options we require for 
          # acts_as_journalized to work, as follows:
          # # type is the supplied or the pluralized class name
          # # timestamp is supplied or the journal's created_at
          # # author_key will always be the journal's author
          # #
          # # find_options are merged as follows:
          # # # select statement is enriched with the journal fields
          # # # journal association is added to the includes
          # # # if a project is associated with the model, this is added to the includes
          # # # the find conditions are extended to only choose journals which have the proper activity_type
          # => a valid activity hash
          def journalized_activity_hash(options)
            options.tap do |h|
              h[:type] ||= plural_name
              h[:timestamp] = "#{journal_class.table_name}.created_at"
              h[:author_key] = "#{journal_class.table_name}.user_id"

              h[:find_options] ||= {} # in case it is nil
              h[:find_options] = {}.tap do |opts|
                cond = ARCondition.new
                cond.add(["#{journal_class.table_name}.activity_type = ?", h[:type]])
                cond.add(h[:find_options][:conditions]) if h[:find_options][:conditions]
                opts[:conditions] = cond.conditions

                opts[:include] = [:versioned]
                opts[:include] += h[:find_options][:include] if h[:find_options][:include]
                opts[:include].uniq!

                #opts[:joins] = h[:find_options][:joins] if h[:find_options][:joins]
              end
            end
          end

          # Merges the event hashes defaults with the options provided by the user
          # The defaults take their details from the journal
          def journalized_event_hash(options)
            unless options.has_key? :url
              options[:url] = Proc.new do |journal|
                { :controller => plural_name,
                  :action => 'show',
                  :id => journal.versioned.id,
                  :anchor => "note-#{journal.version}" }
              end
            end
            { :description => :notes, :author => :user }.reverse_merge options
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
            # A new journal was created: make sure the user is set properly
            current_journal.update_attribute(:user_id, @journal_user.id)
          end

          if @custom_values_before_save
            # Has custom values from init_journal_notes
            changed_custom_values = current_custom_values - @custom_values_before_save
          end

          unless changed_custom_values.empty? && (@notes ||= params[:notes]).empty?
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
        # This the method '-' to the singleton class of the custom values hash, so the 
        # code for getting the difference between old and new custom values looks semantically correct
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
