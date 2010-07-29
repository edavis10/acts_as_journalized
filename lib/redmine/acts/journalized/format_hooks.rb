module Redmine::Acts::Journalized
  module FormatHooks
    def self.included(base)
      base.extend ClassMethods
    end
    
    module ClassMethods
      # Shortcut to register a formatter for a number of fields
      def register_on_journal_formatter(formatter, *field_names)
        formatter = formatter.to_sym
        field_names.collect(&:to_s).each do |field|
          JournalFormatter.register :class => self.journal_class.name.to_sym, field => formatter
        end
      end

      # Shortcut to register a new proc as a named formatter. Overwrites
      # existing formatters with the same name
      def register_journal_formatter(formatter)
        JournalFormatter.register formatter.to_sym => Proc.new
      end
    end
  end
end
