require File.dirname(__FILE__) + '/lib/acts_as_journalized'
ActiveRecord::Base.send(:include, Redmine::Acts::Journalized)

# this is for compatibility with current trunk
# once the plugin is part of the core, this will not be needed
# patches should then be ported onto the core
require 'dispatcher'
Dispatcher.to_prepare do
  # Model Patches
  require_dependency File.dirname(__FILE__) + '/lib/acts_as_journalized/journal_patch'
end
