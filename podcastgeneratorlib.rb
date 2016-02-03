require 'time'
require 'shellwords'
require 'uri'
require 'cgi'
require 'net/http'
require 'net/sftp'
require 'openssl'
require 'netrc'
require 'digest'
require 'tmpdir'
require 'rexml/document'
require 'rss'
require 'fileutils'

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

	def self.new_item(title, url, pubdate, filesize, mimetype)
		item = RSS::Rss::Channel::Item.new
		item.guid = RSS::Rss::Channel::Item::Guid.new
		item.enclosure= RSS::Rss::Channel::Item::Enclosure.new

		item.title = title
		item.pubDate = pubdate.httpdate
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
            rescue ArgumentError
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
			title = File.basename(uri.path)
			pubdate = DateTime.httpdate(response["last-modified"])
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
        pubdate = DateTime.httpdate(item.elements["pubDate"].text)
        filesize = item.elements["enclosure"].attributes["length"]
        mimetype = item.elements["enclosure"].attributes["type"]
        return new_item(title, url, pubdate, filesize, mimetype)
	end
end

def sync_youtube_playlist(url, downloadfolderpath, formatcode)
	downloadfolderpath += "/" unless downloadfolderpath[-1] == "/"
	command = "youtube-dl "
	command += "--max-downloads 10 "
	command += "--playlist-end 10 "
	command += "--youtube-skip-dash-manifest "
	command += "-f #{formatcode} " if formatcode
	command += "--dateafter today-2days "
	command += "-o \"#{downloadfolderpath}%(title)s-%(id)s.%(ext)s\" "
	command += "\"#{url}\""
	return system(command)
end

def download_youtube_video(url, downloadfolderpath, formatcode)
	downloadfolderpath += "/" unless downloadfolderpath[-1] == "/"
	command = "youtube-dl "
	command += "--youtube-skip-dash-manifest "
	command += "-f #{formatcode} " if formatcode
	command += "-o #{downloadfolderpath}\"%(title)s-%(id)s.%(ext)s\" "
	command += "\"#{url}\""
	return system(command)
end

def parse_url(url, netrcfile = nil)
	uri = URI(URI.escape(url))
	if netrcfile
		credentials = Netrc.read(netrcfile)[uri.host]
		uri.user = URI.escape(credentials[0])
		uri.password = URI.escape(credentials[1])
	end
	return uri
end

def index_local_directory(localpath, httpfolderurl, netrcfile = nil)
	filepaths = []

	Dir::entries(localpath).each do |entry|
		filepath = File.join(localpath, entry)
		if File.ftype(filepath) == "file"
			filepaths << filepath
		end
	end

	uris = build_uris_for_files(filepaths, httpfolderurl, netrcfile)

	items = []
	uris.each do |uri|
		items << Podcast.construct_item_from_uri(uri)
	end

	return items
end

def index_remote_directory(hostname, remotepath, httpfolderurl, netrcfile = nil)
	username, password = Netrc.read(netrcfile)[hostname]
	filepaths = []
	Net::SFTP.start(hostname, username, :password => password) do |sftp|
		sftp.dir.entries(remotepath).each do |file|
			filepaths << File.join(remotepath, file.name) unless file.directory?
		end
	end

	uris = build_uris_for_files(filepaths, httpfolderurl, netrcfile)

	items = []
	uris.each do |uri|
		items << Podcast.construct_item_from_uri(uri)
	end

	return items
end

def build_uris_for_files(filepaths, httpfolderurl, netrcfile = nil)
	folderURI = parse_url(httpfolderurl, netrcfile)
	uris	= []
	filepaths.each do |filepath|
		escaped = URI.escape(File.basename(filepath))
		uris << URI.join(folderURI, escaped)
	end
	return uris
end

def parse_media_list(media_list_path)
	items = []
	lines = open(media_list_path).read.split("\n").map(&:strip)
	lines.each do |line|
		split = line.split("||")
		type = split.slice!(0)
		path = split.slice!(-1)
		arguments = split
		items << [type.downcase, arguments, path]
	end
	return items
end

#an example use case for this is in aggregator.rb in the example_scripts folder
def handle_media_list(media_list_path, media_folder, media_folder_url,
								server_settings, netrc_file_path)
	items = []
	parse_media_list(media_list_path).each do |type, arguments, path|
		case type
		when "fileurl"
			uri = parse_url(path)
			items << Podcast.construct_item_from_uri(uri)

		when "youtubeplaylistsubscription"
			format, url = arguments[0], path
			sync_youtube_playlist(url, media_folder, format)

		when "youtubedl"
			format, url = arguments[0], path
			download_youtube_video(url, media_folder, format)

		when "remoteserver"
			settings = server_settings[arguments[0].downcase]
			folder_url = [settings[1], path].join("/")
			hostname = settings[0]
			items += index_remote_directory(hostname, path,
								folder_url, netrc_file_path)
		else
			puts "No handler for #{type}"
		end
	end

	items += index_local_directory(media_folder, media_folder_url,
												netrc_file_path)
	return items
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
