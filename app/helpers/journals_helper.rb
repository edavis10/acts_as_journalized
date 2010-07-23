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

  def render_journal(issue, journal)
    label = journal.version == 1 ? :label_added_time_by : :label_updated_time_by
    journal_content = render_journal_details(journal, label)
    journal_content += render_notes(issue, journal, :reply_links => authorize_for('issues', 'edit')) unless journal.notes.blank?
    content_tag "div", journal_content, { :id => "change-#{journal.id}", :class => "journal" }
  end

  # This renders a journal entry wiht a header and details
  def render_journal_details(journal, header_label = :label_updated_time_by)
    header = <<-HTML
      <h4>
        <div style="float:right;">#{link_to "##{journal.version}", :anchor => "note-#{journal.version}"}</div>
        #{avatar(journal.user, :size => "24")}
        #{content_tag('a', '', :name => "note-#{journal.version}")}
        #{authoring journal.created_at, journal.user, :label => header_label}
      </h4>
    HTML

    if journal.details.any?
      details = content_tag "ul", :class => "details" do
        journal.details.collect do |detail|
          if d = journal.render_detail(detail)
            content_tag("li", d)
          end
        end.compact
      end
    end

    content_tag("div", "#{header}#{details}", :id => "change-#{journal.id}", :class => "journal")
  end

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

end
