require_dependency 'journal_observer'

module Redmine::Acts::Journalized
  module JournalObserverPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      
      # Same as typing in the class 
      base.class_eval do
        unloadable
        
        alias_method_chain :after_create, :acts_as_journalized
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      def after_create_with_acts_as_journalized(journal)
        if journal.journalized_type == "Issue"
          after_create_without_acts_as_journalized(journal)
        end
      end
    end
  end
end

JournalObserver.send(:include, Redmine::Acts::Journalized::JournalObserverPatch)
