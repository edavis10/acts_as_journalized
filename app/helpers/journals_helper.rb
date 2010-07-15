# redMine - project management software
# Copyright (C) 2006-2008  Jean-Philippe Lang
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

module JournalsHelper
  unloadable
  include ApplicationHelper
  include ActionView::Helpers::TagHelper

  def render_notes(issue, journal, options={})
    if User.current.logged?
      editable = User.current.allowed_to?(:edit_issue_notes, issue.project) || nil
      if journal.user == User.current
        editable ||= User.current.allowed_to?(:edit_own_issue_notes, issue.project)
      end
    end

    unless journal.notes.blank?
      links = returning [] do |l|
        if options[:reply_links]
          l << link_to_remote(image_tag('comment.png'),
                { :url => { :controller => 'issues', :action => 'reply',
                            :id => issue, :journal_id => journal} },
                  :title => l(:button_quote))
        end
        if editable
          l << link_to_in_place_notes_editor(image_tag('edit.png'), "journal-#{journal.id}-notes",
                { :controller => 'journals', :action => 'edit', :id => journal },
                  :title => l(:button_edit))
        end
      end
    end

    content = ''
    content << content_tag('div', links.join(' '), :class => 'contextual') unless links.empty?
    content << textilizable(journal, :notes)

    css_classes = "wiki"
    css_classes << " editable" if editable

    content_tag('div', content, :id => "journal-#{journal.id}-notes", :class => css_classes)
  end

  def link_to_in_place_notes_editor(text, field_id, url, options={})
    onclick = "new Ajax.Request('#{url_for(url)}', {asynchronous:true, evalScripts:true, method:'get'}); return false;"
    link_to text, '#', options.merge(:onclick => onclick)
  end

  def format_attribute_detail(key, values, no_html=false)
    field = key.to_s.gsub(/\_id$/, "")
    label = l(("field_" + field).to_sym)

    formatter = case key
    when 'due_date', 'start_date'
      Proc.new {|v| format_date(v.to_date) }
    when 'project_id', 'status_id', 'tracker_id', 'assigned_to_id', 'priority_id', 'category_id', 'fixed_version_id'
      Proc.new {|v| find_name_by_reflection(field, v) }
    when 'estimated_hours'
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
    old_value = content_tag("i", h(old_value)) if old_value
    old_value = content_tag("strike", old_value) if old_value and value.empty?
    [label, old_value, value]
  end

  def show_detail(detail, no_html=false)
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
    return "" unless label || old_value || value # print nothing if there are no values
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
