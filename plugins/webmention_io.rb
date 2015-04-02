#  (c) Aaron Gustafson
#  https://github.com/aarongustafson/jekyll-webmention_io 
#  Licence : MIT
#  
#  this liquid plugin insert a webmentions into your Octopress or Jekill blog
#  using http://webmention.io/ and the following syntax:
#
#    {% webmentions URL %}
#    {% webmention_count URL %}
#   
require 'json'
require 'net/http'

WEBMENTION_CACHE_DIR = File.expand_path('../../.webmention-cache', __FILE__)
FileUtils.mkdir_p(WEBMENTION_CACHE_DIR)

module Jekyll
  
  class Webmentions < Liquid::Tag
    
    def initialize(tagName, text, tokens)
      super
      @text = text
      @api_endpoint = ""
    end
    
    def render(context)
      output = super
      
      targets = []
      
      args = @text.split(/\s+/).map(&:strip)
      args.each do |url|
        target = lookup(context, url)
        targets.push(target)
        # For legacy (non www) URIs
        legacy = target.sub "www.", ""
        targets.push(legacy)
      end
      
      api_params = targets.collect { |v| "target[]=#{v}" }.join("&")
      response = get_response(api_params)

      site = context.registers[:site]
      @converter = site.getConverterImpl(::Jekyll::Converters::Markdown)

      html_output_for(response)
    end

    def html_output_for(response)
      ""
    end
    
    def url_params_for(api_params)
      api_params.keys.sort.map do |k|
        "#{CGI::escape(k)}=#{CGI::escape(api_params[k])}"
      end.join('&')
    end

    def get_response(api_params)
      api_uri = URI.parse(@api_endpoint + "?#{api_params}")
      # print api_uri
      # print "\r\n"
      response = Net::HTTP.get(api_uri.host, api_uri.request_uri)
      if response
        # print response
        JSON.parse(response)
      else
        ""
      end
    end
    
    def lookup(context, name)
      lookup = context

      name.split(".").each do |value|
        lookup = lookup[value]
      end

      lookup
    end

  end
  
  class WebmentionsTag < Webmentions
  
    def initialize(tagName, text, tokens)
      super
      @api_endpoint = "http://webmention.io/api/mentions"
    end

    def html_output_for(response)
      body = "<p class=\"webmentions__not-found\">No webmentions were found</p>"
      
      if response and response['links']
        webmentions = parse_links(response['links'])
      end

      if webmentions
        body = webmentions
      end
      
      "<div class=\"webmentions\">#{body}</div>"
    end
    
    def parse_links(links)
      
      # load from the cache
      cache_file = File.join(WEBMENTION_CACHE_DIR, "recieved_webmentions.yml")
      if File.exists?(cache_file)
        cached_webmentions = open(cache_file) { |f| YAML.load(f) }
      else
        cached_webmentions = {}
      end
      
      lis = ""

      links.reverse_each { |link|
        
        id = link["id"]
        
        if ! cached_webmentions[id]
          
          webmention = ""
          webmention_classes = "webmention"
          
          title = link["data"]["name"]
          content = link["data"]["content"]
          url = link["data"]["url"] || link["source"]
          type = link["activity"]["type"]
          sentence = link["activity"]["sentence_html"]

          activity = false
          if type == "like" or type == "repost"
            activity = true
          end
          
          link_title = false
          if !( title and content ) and url
            url = link["source"]
            
            status = `curl -s -I -L -o /dev/null -w "%{http_code}" --location "#{url}"`
            next if status != "200"
            
            # print "checking #{url}\r\n"
            html_source = `curl -s --location "#{url}"`
            
            if ! html_source.valid_encoding?
              html_source = html_source.encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
            end

            matches = /<title>(.*)<\/title>/.match( html_source )
            if matches
              title = matches[1].strip
            else
              matches = /<h1>(.*)<\/h1>/.match( html_source )
              if matches
                title = matches[1].strip
              else
                title = "No title available"
              end
            end
            
            title = title.gsub(%r{</?[^>]+?>}, '')
            link_title = title
          end

          # make sure non-activities also get a link_title
          if !( activity and link_title )
            link_title = title
          end

          # except replies
          if type == "reply"
            link_title = false
          end

          # no duplicate content
          if title and content and title == content
            title = false
            link_title = false
          end

          # truncation
          if content and content.length > 200 
            content = content[0..200].gsub(/\s\w+\s*$/, '...')
          end

          if ! id
            time = Time.now();
            id = time.strftime("%s")
          end

          author_block = ""
          if author = link["data"]["author"]

            # puts author
            a_name = author["name"]
            a_url = author["url"]
            a_photo = author["photo"]

            if a_photo
              status = `curl -s -I -L -o /dev/null -w "%{http_code}" --location "#{a_photo}"`
              if status == "200"
                author_block << "<img class=\"webmention__author__photo u-photo\" src=\"#{a_photo}\" alt=\"\" title=\"#{a_name}\">"
              else
                webmention_classes << " webmention--no-photo"
              end
            end

            name_block = "<b class=\"p-name\">#{a_name}</b>"
            author_block << name_block

            if a_url
              author_block = "<a class=\"u-url\" href=\"#{a_url}\">#{author_block}</a>"
            end

            author_block = "<div class=\"webmention__author p-author h-card\">#{author_block}</div>"

            if activity
              link_title = "#{a_name} #{title}"
              webmention_classes << ' webmention--author-starts'
            end

          elsif
            webmention_classes << " webmention--no-author"
          end

          # API change. The content now loses the person.
          #if author and title and content and title == "#{author["name"]} #{content}"
          #  link_title = title
          #end

          published_block = ""
          pubdate = link["data"]["published_ts"]
          if pubdate
            pubdate = Time.at(pubdate)
          elsif link["verified_date"]
            pubdate = Time.parse(link["verified_date"])
          end
          if pubdate
            pubdate_iso = pubdate.strftime("%FT%T%:z")
            pubdate_formatted = pubdate.strftime("%-d %B %Y")
            published_block = "<time class=\"webmention__pubdate dt-published\" datetime=\"#{pubdate_iso}\">#{pubdate_formatted}</time>"
          elsif
            webmention_classes << " webmention--no-pubdate"
          end

          meta_block = ""
          if published_block
            meta_block << published_block
          end
          if ! link_title
            if published_block and url
              meta_block << " | "
            end
            if url
              meta_block << "<a class=\"webmention__source u-url\" href=\"#{url}\">Permalink</a>"
            end
          end
          if meta_block
            meta_block = "<div class=\"webmention__meta\">#{meta_block}</div>"
          end

          if a_name and ( ( title and title.start_with?(a_name) ) or ( content and content.start_with?(a_name) ) )
            webmention_classes << ' webmention--author-starts'
          end

          # Build the content block
          content_block = ""
          if link_title

            link_title = link_title.sub "reposts", "reposted"
            
            webmention_classes << " webmention--title-only"

            content_block = "<a href=\"#{url}\">#{link_title}</a>"
            
            # build the block
            content_block = " <div class=\"webmention__title p-name\">#{content_block}</div>"
            
          else
            
            webmention_classes << " webmention--content-only"
            
            # like, repost
            if activity and sentence
              content = sentence.sub /href/, "class=\"p-author h-card\" href"
            # everything else
            else
              content = @converter.convert("#{content}")
            end

            content_block << "<div class=\"webmention__content p-content\">#{content}</div>"

          end

          # meta
          content_block << meta_block
            
          # put it together
          webmention << "<li id=\"webmention-#{id}\" class=\"webmentions__item\">"
          webmention << "<article class=\"h-cite #{webmention_classes}\">"
          
          webmention << author_block
          webmention << content_block
          webmention << "</article></li>"

          cached_webmentions[id] = webmention
          
        end
        
        lis << cached_webmentions[id]
        
      }
      
      # store it all back in the cache
      File.open(cache_file, 'w') { |f| YAML.dump(cached_webmentions, f) }
      
      if lis != ""
        "<ol class=\"webmentions__list\">#{lis}</ol>"
      end
    end

  end

  class WebmentionCountTag < Webmentions
    
    def initialize(tagName, text, tokens)
      super
      @api_endpoint = "http://webmention.io/api/count"
    end

    def html_output_for(response)
      count = response['count'] || "0"
      "<span class=\"webmention-count\">#{count}</span>"
    end
    
  end
  
  class WebmentionGenerator < Generator
    safe true
    priority :low
    
    def generate(site)
      webmentions = {}
      if defined?(WEBMENTION_CACHE_DIR)
        cache_file = File.join(WEBMENTION_CACHE_DIR, "webmentions.yml")
        site.posts.each do |post|
          source = "#{site.config['url']}#{post.url}"
          targets = []
          if post.data['in_reply_to']
            targets.push(post.data['in_reply_to'])
          end
          post.content.scan(/(?:https?:)?\/\/[^\s)#"]+/) do |match|
            if ! targets.find_index( match )
              targets.push(match)
            end
          end
          webmentions[source] = targets
        end
        File.open(cache_file, 'w') { |f| YAML.dump(webmentions, f) }
      end
    end
  end
  
end

Liquid::Template.register_tag('webmentions', Jekyll::WebmentionsTag)
Liquid::Template.register_tag('webmention_count', Jekyll::WebmentionCountTag)