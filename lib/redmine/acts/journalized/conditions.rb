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
  # Allows version creation to occur conditionally based on given <tt>:if</tt> and/or
  # <tt>:unless</tt> options.
  module Conditions
    def self.included(base) # :nodoc:
      base.class_eval do
        extend ClassMethods
        include InstanceMethods

        alias_method_chain :create_version?, :conditions
        alias_method_chain :update_version?, :conditions

        class << self
          alias_method_chain :prepare_versioned_options, :conditions
        end
      end
    end

    # Class methods on ActiveRecord::Base to prepare the <tt>:if</tt> and <tt>:unless</tt> options.
    module ClassMethods
      # After the original +prepare_versioned_options+ method cleans the given options, this alias
      # also extracts the <tt>:if</tt> and <tt>:unless</tt> options, chaning them into arrays
      # and converting any symbols to procs. Procs are called with the ActiveRecord model instance
      # as the sole argument.
      #
      # If all of the <tt>:if</tt> conditions are met and none of the <tt>:unless</tt> conditions
      # are unmet, than version creation will proceed, assuming all other conditions are also met.
      def prepare_versioned_options_with_conditions(options)
        result = prepare_versioned_options_without_conditions(options)

        self.vestal_versions_options[:if] = Array(options.delete(:if)).map(&:to_proc)
        self.vestal_versions_options[:unless] = Array(options.delete(:unless)).map(&:to_proc)

        result
      end
    end

    # Instance methods that determine based on the <tt>:if</tt> and <tt>:unless</tt> conditions,
    # whether a version is to be create or updated.
    module InstanceMethods
      private
        # After first determining whether the <tt>:if</tt> and <tt>:unless</tt> conditions are
        # satisfied, the original, unaliased +create_version?+ method is called to determine
        # whether a new version should be created upon update of the ActiveRecord::Base instance.
        def create_version_with_conditions?
          version_conditions_met? && create_version_without_conditions?
        end

        # After first determining whether the <tt>:if</tt> and <tt>:unless</tt> conditions are
        # satisfied, the original, unaliased +update_version?+ method is called to determine
        # whther the last version should be updated to include changes merged from the current
        # ActiveRecord::Base instance update.
        #
        # The overridden +update_version?+ method simply returns false, effectively delegating
        # the decision to whether the <tt>:if</tt> and <tt>:unless</tt> conditions are met.
        def update_version_with_conditions?
          version_conditions_met? && update_version_without_conditions?
        end

        # Simply checks whether the <tt>:if</tt> and <tt>:unless</tt> conditions given in the
        # +versioned+ options are met: meaning that all procs in the <tt>:if</tt> array must
        # evaluate to a non-false, non-nil value and that all procs in the <tt>:unless</tt> array
        # must all evaluate to either false or nil.
        def version_conditions_met?
          vestal_versions_options[:if].all?{|p| p.call(self) } && !vestal_versions_options[:unless].any?{|p| p.call(self) }
        end
    end
  end
end
