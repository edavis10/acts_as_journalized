require_dependency 'journal_formatter'

# The ActiveRecord model representing versions.
class Journal < ActiveRecord::Base
  unloadable

  include Comparable
  include JournalFormatter

  # Make sure each journaled model instance only has unique version ids
  validates_uniqueness_of :version, :scope => [:versioned_id]

  # ActiveRecord::Base#changes is an existing method, so before serializing the +changes+ column,
  # the existing +changes+ method is undefined. The overridden +changes+ method pertained to
  # dirty attributes, but will not affect the partial updates functionality as that's based on
  # an underlying +changed_attributes+ method, not +changes+ itself.
  # undef_method :changes
  serialize :changes, Hash

  # In conjunction with the included Comparable module, allows comparison of version records
  # based on their corresponding version numbers, creation timestamps and IDs.
  def <=>(other)
    [version, created_at, id].map(&:to_i) <=> [other.version, other.created_at, other.id].map(&:to_i)
  end

  # Returns whether the version has a version number of 1. Useful when deciding whether to ignore
  # the version during reversion, as initial versions have no serialized changes attached. Helps
  # maintain backwards compatibility.
  def initial?
    number == 1
  end

  # Possible shortcut to the associated project
  def project
    if versioned.respond_to?(:project)
      versioned.project
    elsif versioned.is_a? Project
      versioned
    else
      nil
    end
  end

  def editable_by?(user)
    versioned.journal_editable_by?(user)
  end

  def details
    attributes["changes"]
  end

  # Backwards compatibility with old-style timestamps
  def created_on
    created_at
  end

  def method_missing(method, *args, &block)
    begin
      versioned.send(method, *args, &block)
    rescue NoMethodError => e
      e.name.to_sym == method ? super(method, *args, &block) : raise(e)
    end
  end
end
