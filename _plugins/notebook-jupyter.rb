require 'json'
require 'fileutils'
require './_plugins/notebook'

module Jekyll
  class JupyterNotebookGenerator < Generator
    safe true

    def generate(site)
      # For every tutorial with the 'notebook' key in the page data
      site.pages.select { |page| GTNNotebooks.notebook_filter(page.data) }.each do |page|
        # We get the path to the tutorial source
        dir = File.dirname(File.join('.', page.url))
        fn = File.join('.', page.url).sub(/html$/, 'md')
        notebook_language = page.data['notebook'].fetch('language', 'python')

        # Tag our source page
        page.data['tags'] = [] unless page.data.has_key? 'tags'
        page.data['tags'].push('jupyter-notebook')

        puts "[GTN/Notebooks] Rendering #{notebook_language} #{fn}"
        last_modified = begin page.last_modified.to_s rescue Time.new.to_s end
        notebook = GTNNotebooks.render_jupyter_notebook(page.data, page.content, page.url, last_modified, notebook_language, site, dir)

        topic_id = dir.split('/')[-3]
        tutorial_id = dir.split('/')[-1]

        # Write it out!
        page2 = PageWithoutAFile.new(site, '', dir, "#{topic_id}-#{tutorial_id}.ipynb")
        page2.content = JSON.pretty_generate(notebook)
        page2.data['layout'] = nil
        page2.data['citation_target'] = 'jupyter'
        site.pages << page2

        # Create a no-solutions version:
        no_solutions = notebook.clone

        no_solutions['cells'] = no_solutions['cells'].map{|cell|
          if cell.fetch('cell_type') == 'markdown'
            if cell['source'].is_a? String
              cell['source'].gsub!(/<blockquote class="solution"[^>]*>/, "<blockquote class=\"solution\" style=\"display:none\">")
            end
          end
          cell
        }

        page2 = PageWithoutAFile.new(site, '', dir, "#{topic_id}-#{tutorial_id}-course.ipynb")
        page2.content = JSON.pretty_generate(no_solutions)
        page2.data['layout'] = nil
        page2.data['citation_target'] = 'jupyter'
        site.pages << page2

      end
    end
  end
end
