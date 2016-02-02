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

CachePath = File.join(Dir.tmpdir, "podcastgenerator")
Dir.mkdir(CachePath) unless Dir.exist?(CachePath)

MIMETypeCommand = "file --mime-type "

class Podcast
	def initialize(rssurl, title, description)
		@items = []
		@rss_url = rssurl
		@title = title
		@description = description
	end

	attr_accessor :items

	def generate_header()
		header = ['<?xml version="1.0" encoding="UTF-8"?>']
		header << '<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">'
		header << '<channel>'
		header << "<atom:link href=\"%s\" rel=\"self\" type=\"application/rss+xml\"/>" % @rss_url
		header << bracketize_xml("link", @rss_url)
		header << bracketize_xml("title", @title)
		header << bracketize_xml("description", @description)
		return header.join("\n")
	end

	def get_xml()
		itemsxml = []

		@items.each do |item|
			itemsxml << item.get_xml
		end
		return generate_header + itemsxml.join("\n\n") + generate_footer
	end

	def generate_footer()
		return ['</channel>', '</rss>'].join("\n")
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

	def get_xml()
		lines = ['<item>']
		lines << bracketize_xml('title', CGI.escapeHTML(@title))
		lines << bracketize_xml('link', @url)
		lines << "<guid isPermaLink=\"false\">%s</guid>" % @url
		lines << bracketize_xml('pubDate', @pubdate.httpdate)
		lines << "<enclosure%s%s%s/>" % [ parameterize_xml(" url", @url),
								parameterize_xml(" type", @mimetype),
								parameterize_xml(" length", @filesize) ]
		lines << '</item>'
		return lines.join("\n")
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
		escapedpath = Shellwords.escape(localfilepath)

		@title = filename
		@url = uri.to_s
		@filesize = File.size(localfilepath)
		@mimetype = `#{MIMETypeCommand + escapedpath}`.split(": ")[1].strip
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

def bracketize_xml(tagname, content)
	return "<%s>%s</%s>" % [tagname, content, tagname]
end

def escape_xml_url(url)
	url = URI.escape(url.to_s)
	url = url.gsub("&", "%26").gsub("'", "%27")
	return url
end

def unescape_xml_url(url)
	url = URI.unescape(url)
	url = url.gsub("%26", "&").gsub("%27", "'")
	return url
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

def parameterize_xml(paramatername, string)
	return "%s=\"%s\"" % [paramatername, string]
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


