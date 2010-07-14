require File.expand_path("../lib/acts_as_journalized", __FILE__)
ActiveRecord::Base.send(:include, Redmine::Acts::Journalized)

# this is for compatibility with current trunk
# once the plugin is part of the core, this will not be needed
# patches should then be ported onto the core
require 'dispatcher'
Dispatcher.to_prepare do
  # Patches
  # require_dependency File.dirname(__FILE__) + '/lib/acts_as_journalized/journal_patch'
  # require_dependency File.dirname(__FILE__) + '/lib/acts_as_journalized/journal_observer_patch'
  # require_dependency File.dirname(__FILE__) + '/lib/acts_as_journalized/activity_fetcher_patch'
end
