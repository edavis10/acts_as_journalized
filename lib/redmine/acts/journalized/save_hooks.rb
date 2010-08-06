# This file is part of the acts_as_journalized plugin for the redMine
# project management software
#
# Copyright (C) 2010  Finn GmbH, http://finn.de
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# These hooks make sure journals are properly created and updated with Redmine user detail,
# notes and associated custom fields
module Redmine::Acts::Journalized
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
      @journal_user ||= user
      if self.respond_to? :custom_values
        @custom_values_before_save = custom_values.inject({}) do |hash, cv|
          hash[cv.custom_field_id] = cv.value
          hash
        end
      end
      @current_journal = current_journal
    end

    # Saves the notes and custom value changes in the last Journal
    # Called after_save
    def update_journal
      unless current_journal == @current_journal
        # A new journal was created: make sure the user is set properly
        current_journal.update_attribute(:user_id, @journal_user.id)
      end

      if @custom_values_before_save
        # Has custom values from init_journal_notes
        changed_custom_values = current_custom_values - @custom_values_before_save
      end

      if (changed_custom_values && !changed_custom_values.empty?) || !@notes.empty?
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
      current_journal.update_attribute(:user_id, @journal_user.id)
      current_journal.update_attribute(:notes, @notes)
      combined_changes = current_journal.changes.merge(changed_custom_values)
      current_journal.update_attribute(:changes, combined_changes.to_yaml)
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