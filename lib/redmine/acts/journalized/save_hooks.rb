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
        
        attr_accessor :journal_notes, :journal_user
      end
    end

    # Saves the current custom values, notes and journal to include them in the next journal
    # Called before save
    def init_journal(user = User.current, notes = "")
      self.journal_notes ||= notes
      self.journal_user ||= user
      @associations_before_save ||= {}

      @associations = {}
      save_possible_association :custom_values, :key => :custom_field_id, :value => :value
      save_possible_association :attachments, :key => :id, :value => :filename

      @current_journal ||= last_journal
    end

    # Saves the notes and custom value changes in the last Journal
    # Called after_save
    def update_journal
      unless @associations.empty?
        changed_associations = {}
        changed_associations.merge!(possibly_updated_association :custom_values)
        changed_associations.merge!(possibly_updated_association :attachments)
      end

      unless changed_associations.blank?
        update_extended_journal_contents(changed_associations)
      end
      if last_journal.user != @journal_user
        last_journal.update_attribute(:user_id, @journal_user.id)
      end
      @current_journal = @journal_notes = @journal_user = nil
    end

    def save_possible_association(method, options)
      @associations[method] = options
      if self.respond_to? method
        @associations_before_save[method] ||= send(method).inject({}) do |hash, cv|
          hash[cv.send(options[:key])] = cv.send(options[:value])
          hash
        end
      end
    end

    def possibly_updated_association(method)
      if @associations_before_save[method]
        # Has custom values from init_journal_notes
        return changed_associations(method, @associations_before_save[method])
      end
      {}
    end

    # Saves the notes and changed custom values to the journal
    # Creates a new journal, if no immediate attributes were changed
    def update_extended_journal_contents(changed_associations)
      if last_journal == @current_journal
        # No attribute changes, create a new journal entry
        # on which notes and changed custom values will be written
        create_journal
      end
      combined_changes = last_journal.changes.merge(changed_associations)
      last_journal.update_attribute(:changes, combined_changes.to_yaml)
    end

    def changed_associations(method, previous)
      send(method).reload # Make sure the associations are reloaded
      send(method).inject({}) do |hash, c|
        key = c.send(@associations[method][:key])
        new_value = c.send(@associations[method][:value])

        if previous[key].blank? && new_value.blank?
          # The key was empty before, don't add a blank value
        elsif previous[key] != new_value
          # The key's value changed
          hash["#{method}#{key}"] = [previous[key], new_value]
        end
        hash
      end
    end

    module ClassMethods
    end
  end
end
