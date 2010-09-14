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
  module Deprecated
    # Old mailer API
    def recipients
      notified = project.notified_users
      notified.reject! {|user| !visible?(user)}
      notified.collect(&:mail)
    end

    def current_journal
      last_journal
    end

    deprecate :recipients => "use #last_journal.recipients"
    deprecate :current_journal => "use #last_journal"
  end
end
