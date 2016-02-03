require 'time'
require 'shellwords'
require 'uri'
require 'cgi'
require 'net/http'
require 'net/sftp'
require 'mime/types'
require 'openssl'
require 'netrc'
require 'digest'
require 'tmpdir'
require 'rexml/document'
require 'rss'

#Initialize cache
CachePath = File.join(Dir.tmpdir, "podcastgenerator")
Dir.mkdir(CachePath) unless Dir.exist?(CachePath)

class Podcast
	def initialize(rssurl, title, description)
		@title = title
		@description = description
		@rss_url = rssurl
		@items = []
	end

	attr_accessor :items

	def get_xml()
		rss = RSS::Rss.new("2.0")
		rss.channel  = RSS::Rss::Channel.new

		rss.channel.title = @title
		rss.channel.link = @rss_url
		rss.channel.description = @description

		items.each do |item|
			rss.channel.items << item.get_rss_item
		end

		return rss
	end
end

class PodcastItem
	include Comparable

	def initialize(title = nil, url = nil, pubdate = nil, filesize = nil, mimetype = nil)
		@title = title
		@url = url
		@pubdate = pubdate #This needs to be a DateTime!
		@filesize = filesize
		@mimetype = mimetype
		return self
	end

	attr_reader :title
	attr_reader :url
	attr_reader :pubdate
	attr_reader :filesize
	attr_reader :mimetype

	def <=>(other)
		other.pubdate <=> @pubdate
	end

	def get_rss_item()
		item = RSS::Rss::Channel::Item.new
		item.guid = RSS::Rss::Channel::Item::Guid.new
		item.enclosure= RSS::Rss::Channel::Item::Enclosure.new

		item.title = @title
		item.link = @url
		item.guid.content = @url
		item.guid.isPermaLink = false
		item.pubDate = @pubdate.httpdate
		item.enclosure.length = @filesize
		item.enclosure.url = @url
		item.enclosure.type = @mimetype

		return item
	end

	def construct_item_for_file_uri(uri)
		cached = load_from_cache(uri.to_s)
		if cached
			parseditem = construct_item_from_xml(cached)
			return parseditem unless !parseditem
		end

		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		request = Net::HTTP::Head.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(unescape_xml_url(uri.user),
						unescape_xml_url(uri.password))
		end

		response = http.request(request)

		if response.code == "200"
			@title = File.basename(uri.path)
			@url = uri
			@pubdate = DateTime.httpdate(response["last-modified"])
			@filesize = response["content-length"]
			@mimetype = response["content-type"]
		else
			@title, @url = response.code.to_s, uri
			@pubdate = DateTime.now
		end

		save_to_cache(uri.to_s, get_xml)
		return self
	end

	def construct_item_for_file(localfilepath, uri)
		filename = File.basename(localfilepath)

		@title = filename
		@url = uri.to_s
		@filesize = File.size(localfilepath)
		@mimetype = get_mime_type(localfilepath)
		@pubdate = DateTime.parse(File.mtime(localfilepath).to_s)
		return self
	end

	def construct_item_from_xml(xmlstring)
		item = REXML::XPath.match(REXML::Document.new(xmlstring), "//item")[0]
		return item if !item
		@title = item.elements["title"].text
		@url = URI(item.elements["link"].text)
		@pubdate = DateTime.httpdate(item.elements["pubDate"].text)
		@filesize = item.elements["enclosure"].attributes["length"]
		@mimetype = item.elements["enclosure"].attributes["type"]
		return self
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

def escape_xml_url(url)
	url = URI.escape(url.to_s)
	return url
end

def unescape_xml_url(url)
	url = URI.unescape(url)
	return url
end

def get_mime_type(path)
	path = Shellwords.escape(path)
	command = "file --mime-type "
	return `#{command + path}`.split(": ")[1].strip
end

def parse_url(url, netrcfile = nil)
	uri = URI(escape_xml_url(url))
	if netrcfile
		credentials = Netrc.read(netrcfile)[uri.host]
		uri.user = escape_xml_url(credentials[0])
		uri.password = escape_xml_url(credentials[1])
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
	filepaths.zip(uris).each do |path, uri|
		items << PodcastItem.new.construct_item_for_file(path, uri)
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
		items << PodcastItem.new.construct_item_for_file_uri(uri)
	end

	return items
end

def build_uris_for_files(filepaths, httpfolderurl, netrcfile = nil)
	folderURI = parse_url(httpfolderurl, netrcfile)
	uris	= []
	filepaths.each do |filepath|
		escaped = escape_xml_url(File.basename(filepath))
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
			items << PodcastItem.new.construct_item_for_file_uri(uri)

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
