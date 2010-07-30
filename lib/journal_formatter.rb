# This file is part of the acts_as_journalized plugin for the redMine 
# project management software
#
# Copyright (C) 2010  Finn GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# This module holds the formatting methods that each journal has.
# It provides the hooks to apply different formatting to the details
# of a specific journal.
module JournalFormatter
  unloadable
  mattr_accessor :formatters, :registered_fields
  include ActionView::Helpers::TagHelper
  extend Redmine::I18n

  def self.register(hash)
    if hash[:class]
      klazz = hash.delete(:class)
      registered_fields[klazz] ||= {}
      registered_fields[klazz].merge!(hash)
    else
      formatters.merge(hash)
    end
  end

  # TODO: Document Formatters (can take up to three params, value, versioned, field ...)
  def self.default_formatters
    { :plaintext => (Proc.new {|v,*| v.try(:to_s) }),
      :datetime => (Proc.new {|v,*| format_date(v.to_date) }),
      :named_association => (Proc.new do |value, versioned, field|
        association = versioned.class.reflect_on_association(field.to_sym)
        if association
          record = association.class_name.constantize.find_by_id(id)
          record.name if record
        end
      end),
      :fraction => (Proc.new {|v,*| "%0.02f" % v.to_f }),
      :id => (Proc.new {|v,*| "##{v}" }) }
  end

  self.formatters = default_formatters
  self.registered_fields = {}

  def format_attribute_detail(key, values, no_html=false)
    field = key.to_s.gsub(/\_id$/, "")
    label = l(("field_" + field).to_sym)

    if format = JournalFormatter.registered_fields[self.class.name.to_sym][key]
      formatter = JournalFormatter.formatters[format]
      old_value = formatter.call(values.first, versioned, field) if values.first
      value = formatter.call(values.last, versioned, field) if values.last
      [label, old_value, value]
    else
      return nil
    end
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
    else
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
end