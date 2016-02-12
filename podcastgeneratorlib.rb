require_relative 'http.rb'
require 'time'
require 'rexml/document'
require 'rss'

class Podcast
	def initialize(rss_url, title, description)
		@rss = RSS::Rss.new("2.0")
		@rss.channel = RSS::Rss::Channel.new
		@rss.channel.title = title
		@rss.channel.link = rss_url
		@rss.channel.description = description
        @items = []
	end

    attr_accessor :items

	def to_s()
        #for some reason we can't set the items list directly in the channel
        #  so the only way to maintain abstraction is to add the items to an
        #  empty clone of our channel and then discard it
        clone = @rss.dup
        items.each do |item| clone.channel.items << item end
		return clone.to_s
	end

    def write(filepath)
        open(filepath, "w").write(to_s)
    end

	def self.new_item(title, url, pubdate, filesize, mimetype)
		item = RSS::Rss::Channel::Item.new
		item.guid = RSS::Rss::Channel::Item::Guid.new
		item.enclosure= RSS::Rss::Channel::Item::Enclosure.new

		item.title = title
		item.pubDate = pubdate
		item.enclosure.length = filesize
		item.enclosure.type = mimetype
		item.guid.isPermaLink = false
		item.link, item.guid.content, item.enclosure.url = url, url, url
        return item
	end

	def self.construct_item_from_uri(uri)
		cached = load_from_cache(uri.to_s)
		if cached
            parseditem = construct_item_from_xml(cached)

            if parseditem != nil
                puts "Using cached for: #{uri.path}"
                return parseditem
            end
		end

        response = request_http_header(uri)

		if response.code == "200"
			title = unencode_url(File.basename(uri.path))
			pubdate = response["last-modified"]
			filesize = response["content-length"]
			mimetype = response["content-type"]
            item = new_item(title, uri, pubdate, filesize, mimetype)
            puts "Saving cache for: #{uri.path}"
			save_to_cache(uri.to_s, item)
		else
            item = new_item(response.code, uri, DateTime.now.httpdate , 0, "")
		end

	   return item
	end

	def self.construct_item_from_xml(xmlstring)
        item = REXML::XPath.match(REXML::Document.new(xmlstring), "//item")[0]
        title = item.elements["title"].text
        url = item.elements["link"].text
        pubdate = item.elements["pubDate"].text
        filesize = item.elements["enclosure"].attributes["length"]
        mimetype = item.elements["enclosure"].attributes["type"]
        return new_item(title, url, pubdate, filesize, mimetype)
	end
end


