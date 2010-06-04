module Redmine::Acts::Journalized
  module ActivityFetcherPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      
      # Same as typing in the class 
      base.class_eval do
        unloadable
        alias_method_chain :event_types, :generalized_journal
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      
      # Quickfixes until the journal patches are in redmine proper
      def event_types_with_generalized_journal
        return @event_types unless @event_types.nil?
        @event_types = Redmine::Activity.available_event_types
      end
    end
  end
end

Redmine::Activity::Fetcher.send(:include, Redmine::Acts::Journalized::ActivityFetcherPatch)
