require 'time'
require 'uri'
require 'net/http'
require 'openssl'
require 'netrc'
require 'digest'
require 'tmpdir'
require 'rexml/document'
require 'rss'

#Initialize cache
CachePath = File.join(Dir.tmpdir, "podcastgenerator-#{ENV["USER"]}")
Dir.mkdir(CachePath) unless Dir.exist?(CachePath)

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
            begin
                parseditem = construct_item_from_xml(cached)
            rescue
                parseditem = nil
            end

			return parseditem unless !parseditem
		end

		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		request = Net::HTTP::Head.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(URI.unescape(uri.user), URI.unescape(uri.password))
		end

		response = http.request(request)

		if response.code == "200"
			title = URI.unescape(File.basename(uri.path))
			pubdate = response["last-modified"]
			filesize = response["content-length"]
			mimetype = response["content-type"]
            item = new_item(title, uri, pubdate, filesize, mimetype)
			save_to_cache(uri.to_s, item)
		else
            item = new_item(response.code, uri, DateTime.now.httpdate , 0, "")
		end

	   return item
	end

	def self.construct_item_from_xml(xmlstring)
        item = REXML::XPath.match(REXML::Document.new(xmlstring), "//item")[0]
        title = item.elements["title"].text
        url = URI(item.elements["link"].text)
        pubdate = item.elements["pubDate"].text
        filesize = item.elements["enclosure"].attributes["length"]
        mimetype = item.elements["enclosure"].attributes["type"]
        return new_item(title, url, pubdate, filesize, mimetype)
	end
end


def md5(string)
	return Digest::MD5.new.update(string).hexdigest
end

def save_to_cache(string, data)
	file = open(File.join(CachePath, md5(string)), "w")
	file.write(data)
	file.close()
end

def load_from_cache(string)
	file = File.join(CachePath, md5(string))
	return open(file).read().strip() if File.exists?(file)
	return nil
end
