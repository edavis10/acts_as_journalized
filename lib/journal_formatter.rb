# This module holds the formatting methods that each journal has.
# It provides the hooks to apply different formatting to the details
# of a specific journal.
module JournalFormatter
  unloadable
  include ActionView::Helpers::TagHelper

  def format_attribute_detail(key, values, no_html=false)
    field = key.to_s.gsub(/\_id$/, "")
    label = l(("field_" + field).to_sym)

    formatter = case key
    when 'due_date', 'start_date'
      Proc.new {|v| format_date(v.to_date) }
    when 'project_id', 'status_id', 'tracker_id', 'assigned_to_id', 'priority_id', 'category_id', 'fixed_version_id'
      Proc.new {|v| find_name_by_reflection(field, v) }
    when 'estimated_hours', 'done_ratio'
      Proc.new {|v| "%0.02f" % v.to_f }
    when 'parent_id'
      Proc.new {|v| "##{values.first}" }
    else
      return nil # If we don't know how to format this, ignore it
    end

    old_value = formatter.call(values.first) if values.first
    value = formatter.call(values.last) if values.last

    [label, old_value, value]
  end

  def format_custom_value_detail(custom_field, values, no_html)
    label = custom_field.name
    old_value = format_value(values.first, custom_field.field_format) if values.first
    value = format_value(values.last, custom_field.field_format) if values.last
    
    [label, old_value, value]
  end

  def format_attachment_detail(key, values, no_html)
    label = l(:label_attachment)
    old_value = values.first
    value = values.last

    [label, old_value, value]
  end

  def format_html_attachment_detail(value)
    if !value.blank? && a = Attachment.find_by_id(value)
      # Link to the attachment if it has not been removed
      link_to_attachment(a)
    else
      content_tag("i", h(value)) if value
    end
  end
  
  def format_html_detail(label, old_value, value)
    label = content_tag('strong', label)
    old_value = content_tag("i", h(old_value)) if old_value && !old_value.blank?
    old_value = content_tag("strike", old_value) if old_value and value.blank?
    [label, old_value, value]
  end

  def render_detail(detail, no_html=false)
    key = detail.first
    values = detail.last

    if versioned.class.columns.collect(&:name).include? key
      attr_detail = format_attribute_detail(key, values, no_html)
    elsif key =~ /^\d+$/ && custom_field = CustomField.find_by_id(key.to_i)
      cv_detail = format_custom_value_detail(custom_field, values, no_html)
    elsif
      attachment_detail = format_attachment_detail(key, values, no_html)
    end

    label, old_value, value = attr_detail || cv_detail || attachment_detail
    Redmine::Hook.call_hook :helper_issues_show_detail_after_setting, {:detail => detail,
        :label => label, :value => value, :old_value => old_value }
    return nil unless label || old_value || value # print nothing if there are no values
    label, old_value, value = [label, old_value, value].collect(&:to_s)

    unless no_html
      label, old_value, value = *format_html_detail(label, old_value, value)
      value = format_html_attachment_detail(value) if attachment_detail
    end

    unless value.blank?
      if attr_detail || cv_detail
        unless old_value.blank?
          l(:text_journal_changed, :label => label, :old => old_value, :new => value)
        else
          l(:text_journal_set_to, :label => label, :value => value)
        end
      elsif attachment_detail
        l(:text_journal_added, :label => label, :value => value)
      end
    else
      l(:text_journal_deleted, :label => label, :old => old_value)
    end
  end

  # Find the name of an associated record stored in the field attribute
  def find_name_by_reflection(field, id)
    association = versioned.class.reflect_on_association(field.to_sym)
    if association
      record = association.class_name.constantize.find_by_id(id)
      return record.name if record
    end
  end
end