# This file included as part of the acts_as_journalized plugin for
# the redMine project management software; You can redistribute it
# and/or modify it under the terms of the GNU General Public License
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
#
# The original copyright and license conditions are:
# Copyright (c) 2009 Steve Richert
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module Redmine::Acts::Journalized
  # The control feature allows use of several code blocks that provide finer control over whether
  # a new journal is created, or a previous journal is updated.
  module Control
    def self.included(base) # :nodoc:
      base.class_eval do
        include InstanceMethods

        alias_method_chain :create_journal?, :control
        alias_method_chain :update_journal?, :control
      end
    end

    # Control blocks are called on ActiveRecord::Base instances as to not cause any conflict with
    # other instances of the journaled class whose behavior could be inadvertently altered within
    # a control block.
    module InstanceMethods
      # The +skip_journal+ block simply allows for updates to be made to an instance of a journaled
      # ActiveRecord model while ignoring all new journal creation. The <tt>:if</tt> and
      # <tt>:unless</tt> conditions (if given) will not be evaulated inside a +skip_journal+ block.
      #
      # When the block closes, the instance is automatically saved, so explicitly saving the
      # object within the block is unnecessary.
      #
      # == Example
      #
      #   user = User.find_by_first_name("Steve")
      #   user.journal # => 1
      #   user.skip_journal do
      #     user.first_name = "Stephen"
      #   end
      #   user.journal # => 1
      def skip_journal
        with_journal_flag(:skip_journal) do
          yield if block_given?
          save
        end
      end

      # Behaving almost identically to the +skip_journal+ block, the only difference with the
      # +skip_journal!+ block is that the save automatically performed at the close of the block
      # is a +save!+, meaning that an exception will be raised if the object cannot be saved.
      def skip_journal!
        with_journal_flag(:skip_journal) do
          yield if block_given?
          save!
        end
      end

      # A convenience method for determining whether a journaled instance is set to skip its next
      # journal creation.
      def skip_journal?
        !!@skip_journal
      end

      # Merging journals with the +merge_journal+ block will take all of the journals that would
      # be created within the block and merge them into one journal and pushing that single journal
      # onto the ActiveRecord::Base instance's journal history. A new journal will be created and
      # the instance's journal number will be incremented.
      #
      # == Example
      #
      #   user = User.find_by_first_name("Steve")
      #   user.journal # => 1
      #   user.merge_journal do
      #     user.update_attributes(:first_name => "Steven", :last_name => "Tyler")
      #     user.update_attribute(:first_name, "Stephen")
      #     user.update_attribute(:last_name, "Richert")
      #   end
      #   user.journal # => 2
      #   user.journals.last.changes
      #   # => {"first_name" => ["Steve", "Stephen"], "last_name" => ["Jobs", "Richert"]}
      #
      # See VestalVersions::Changes for an explanation on how changes are appended.
      def merge_journal
        with_journal_flag(:merge_journal) do
          yield if block_given?
        end
        save
      end

      # Behaving almost identically to the +merge_journal+ block, the only difference with the
      # +merge_journal!+ block is that the save automatically performed at the close of the block
      # is a +save!+, meaning that an exception will be raised if the object cannot be saved.
      def merge_journal!
        with_journal_flag(:merge_journal) do
          yield if block_given?
        end
        save!
      end

      # A convenience method for determining whether a journaled instance is set to merge its next
      # journals into one before journal creation.
      def merge_journal?
        !!@merge_journal
      end

      # Appending journals with the +append_journal+ block acts similarly to the +merge_journal+
      # block in that all would-be journal creations within the block are defered until the block
      # closes. The major difference is that with +append_journal+, a new journal is not created.
      # Rather, the cumulative changes are appended to the serialized changes of the instance's
      # last journal. A new journal is not created, so the journal number is not incremented.
      #
      # == Example
      #
      #   user = User.find_by_first_name("Steve")
      #   user.journal # => 2
      #   user.journals.last.changes
      #   # => {"first_name" => ["Stephen", "Steve"]}
      #   user.append_journal do
      #     user.last_name = "Jobs"
      #   end
      #   user.journals.last.changes
      #   # => {"first_name" => ["Stephen", "Steve"], "last_name" => ["Richert", "Jobs"]}
      #   user.journal # => 2
      #
      # See VestalVersions::Changes for an explanation on how changes are appended.
      def append_journal
        with_journal_flag(:merge_journal) do
          yield if block_given?
        end

        with_journal_flag(:append_journal) do
          save
        end
      end

      # Behaving almost identically to the +append_journal+ block, the only difference with the
      # +append_journal!+ block is that the save automatically performed at the close of the block
      # is a +save!+, meaning that an exception will be raised if the object cannot be saved.
      def append_journal!
        with_journal_flag(:merge_journal) do
          yield if block_given?
        end

        with_journal_flag(:append_journal) do
          save!
        end
      end

      # A convenience method for determining whether a journaled instance is set to append its next
      # journal's changes into the last journal changes.
      def append_journal?
        !!@append_journal
      end

      private
        # Used for each control block, the +with_journal_flag+ method sets a given variable to
        # true and then executes the given block, ensuring that the variable is returned to a nil
        # value before returning. This is useful to be certain that one of the control flag
        # instance variables isn't inadvertently left in the "on" position by execution within the
        # block raising an exception.
        def with_journal_flag(flag)
          begin
            instance_variable_set("@#{flag}", true)
            yield
          ensure
            instance_variable_set("@#{flag}", nil)
          end
        end

        # Overrides the basal +create_journal?+ method to make sure that new journals are not
        # created when inside any of the control blocks (until the block terminates).
        def create_journal_with_control?
          !skip_journal? && !merge_journal? && !append_journal? && create_journal_without_control?
        end

        # Overrides the basal +update_journal?+ method to allow the last journal of an journaled
        # ActiveRecord::Base instance to be updated at the end of an +append_journal+ block.
        def update_journal_with_control?
          append_journal?
        end
    end
  end
end
