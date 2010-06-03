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
        perms = self.class.edit_permissions[self.journalized_type]
        if perms
          if perms[:edit_notes]
            edit_notes = usr.allowed_to?(perms[:edit_notes], project)
          end
          if perms[:edit_own_notes]
            edit_own_notes = (self.user == usr && usr.allowed_to?(perms[:edit_own_notes], project))
          end
          
          !!(usr && usr.logged? && (edit_notes || edit_own_notes))
        end
      end
    end
  end
end

Journal.send(:include, Redmine::Acts::Journalized::JournalPatch)