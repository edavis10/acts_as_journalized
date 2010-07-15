module Redmine::Acts::Journalized
  module Permissions
    # Default implementation of journal editing permission
    # Is overridden if defined in the journalized model directly
    def journal_editable_by?(user)
      if respond_to? :editable_by?
        editable_by? user
      else
        p = @project || (project if respond_to? :project)
        options = { :global => p.present? }
        user.allowed_to? :"edit_#{self.class.to_s.pluralize.downcase}", p, options
      end
    end
  end
end
