module Redmine::Acts::Journalized
  # Enables versioned ActiveRecord::Base instances to revert to a previously saved version.
  module Reversion
    def self.included(base) # :nodoc:
      base.class_eval do
        include InstanceMethods
      end
    end

    # Provides the base instance methods required to revert a versioned instance.
    module InstanceMethods
      # Returns the current version number for the versioned object.
      def version
        @version ||= last_version
      end

      def current_journal
        journals.last
      end

      # Accepts a value corresponding to a specific version record, builds a history of changes
      # between that version and the current version, and then iterates over that history updating
      # the object's attributes until the it's reverted to its prior state.
      #
      # The single argument should adhere to one of the formats as documented in the +at+ method of
      # VestalVersions::Versions.
      #
      # After the object is reverted to the target version, it is not saved. In order to save the
      # object after the reversion, use the +revert_to!+ method.
      #
      # The version number of the object will reflect whatever version has been reverted to, and
      # the return value of the +revert_to+ method is also the target version number.
      def revert_to(value)
        to_number = journals.number_at(value)

        changes_between(version, to_number).each do |attribute, change|
          write_attribute(attribute, change.last)
        end

        reset_version(to_number)
      end

      # Behaves similarly to the +revert_to+ method except that it automatically saves the record
      # after the reversion. The return value is the success of the save.
      def revert_to!(value)
        revert_to(value)
        reset_version if saved = save
        saved
      end

      # Returns a boolean specifying whether the object has been reverted to a previous version or
      # if the object represents the latest version in the version history.
      def reverted?
        version != last_version
      end

      private
        # Returns the number of the last created journal in the object's version history.
        #
        # If no associated journals exist, the object is considered at version 1.
        def last_version
          @last_version ||= journals.maximum(:number) || 0
        end

        # Clears the cached version number instance variables so that they can be recalculated.
        # Useful after a new version is created.
        def reset_version(version = nil)
          @last_version = nil if version.nil?
          @version = version
        end
    end
  end
end
