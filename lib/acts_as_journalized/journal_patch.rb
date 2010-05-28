require_dependency 'journal'

module Redmine::Acts::Journalized
  module JournalPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
      
      # Same as typing in the class 
      base.class_eval do
        unloadable
      end
    end
    
    module ClassMethods
    end
    
    module InstanceMethods
      def editable_by?(usr)
        perm = self.class.edit_permissions[self.journalized_type]
        
        
        usr && usr.logged? && (usr.allowed_to?(:edit_issue_notes, project) || (self.user == usr && usr.allowed_to?(:edit_own_issue_notes, project)))
      end
    end
  end
end

Journal.send(:include, Redmine::Acts::Journalized::JournalPatch)