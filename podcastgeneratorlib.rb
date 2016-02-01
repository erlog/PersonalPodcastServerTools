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

CachePath = File.join(Dir.tmpdir, "podcastgenerator")
Dir.mkdir(CachePath) unless Dir.exist?(CachePath)

MIMETypeCommand = "file --mime-type "

class Podcast
	def initialize(rssurl, title, description)
		@items = []
		@rssurl = rssurl
		@title = title
		@description = description
	end
	
	attr_accessor :items

	def generateheader()
		header = ['<?xml version="1.0" encoding="UTF-8"?>']
		header << '<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">'
		header << '<channel>'
		header << "<atom:link href=\"%s\" rel=\"self\" type=\"application/rss+xml\"/>" % @rssurl 
		header << xmlbracketize("link", @rssurl)
		header << xmlbracketize("title", @title)
		header << xmlbracketize("description", @description)
		return header.join("\n")
	end

	def getxml()
		itemsxml = [] 

		@items.each do |item|
			itemsxml << item.getxml
		end
		return generateheader + itemsxml.join("\n\n") + generatefooter
	end

	def generatefooter()
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
		@cached = false
		@cachedxml = nil
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
	
	def getxml()
		return @cachedxml if @cached

		lines = ['<item>']
		lines << xmlbracketize('title', CGI.escapeHTML(@title)) 
		lines << xmlbracketize('link', @url)
		lines << "<guid isPermaLink=\"false\">%s</guid>" % @url
		lines << xmlbracketize('pubDate', @pubdate.httpdate)
		lines << "<enclosure%s%s%s/>" % [ xmlparamaterize(" url", @url), 
								xmlparamaterize(" type", @mimetype),
								xmlparamaterize(" length", @filesize) ] 
		lines << '</item>'
		return lines.join("\n") 
	end

	def constructitemforfileURI(uri)
		cached = loadfromcache(uri.to_s)
		if cached
			@cached = true
			@cachedxml = cached
			puts ["Using cached: ", uri.path].join
			return self
		end	

		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end
		
		request = Net::HTTP::Head.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(unescapexmlurl(uri.user), 
						unescapexmlurl(uri.password)) 
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
		
		savetocache(uri.to_s, getxml)
		return self
	end

	def constructitemforfile(localfilepath, uri)
		filename = File.basename(localfilepath) 
		escapedpath = Shellwords.escape(localfilepath)

		@title = filename
		@url = uri.to_s 
		@filesize = File.size(localfilepath)
		@mimetype = `#{MIMETypeCommand + escapedpath}`.split(": ")[1].strip
		@pubdate = DateTime.parse(File.mtime(localfilepath).to_s)
		return self
	end
end

def syncYouTubePlaylist(url)
	command = "youtube-dl "\
			"--max-downloads 10 "\
			"--playlist-end 10 "\
			"--youtube-skip-dash-manifest "\
			" --date today "\
			"\"%s\"" % url
	return !system(command)
end

def xmlbracketize(tagname, content)
	return "<%s>%s</%s>" % [tagname, content, tagname]
end

def escapexmlurl(url)
	url = URI.escape(url.to_s)
	url = url.gsub("&", "%26").gsub("'", "%27")
	return url
end

def unescapexmlurl(url)
	url = URI.unescape(url)
	url = url.gsub("%26", "&").gsub("%27", "'")
	return url
end

def parseURL(url, netrcfile = nil)
	uri = URI(escapexmlurl(url))
	if netrcfile
		credentials = Netrc.read(netrcfile)[uri.host]
		uri.user = escapexmlurl(credentials[0])
		uri.password = escapexmlurl(credentials[1])
	end
	return uri
end

def xmlparamaterize(paramatername, string)
	return "%s=\"%s\"" % [paramatername, string]
end

def indexlocaldirectory(localpath, httpfolderurl, netrcfile = nil)
	filepaths = []
	Dir::entries(localpath).each do |entry|
		filepath = File.join(localpath, entry)
		if File.ftype(filepath) == "file"
			filepaths << filepath 
		end
	end

	uris = buildURIsforfiles(filepaths, httpfolderurl, netrcfile)

	items = []
	filepaths.zip(uris).each do |path, uri|
		items << PodcastItem.new.constructitemforfile(path, uri)
	end
	return items	
end

def indexremotedirectory(hostname, remotepath, httpfolderurl, netrcfile = nil)
	username, password = Netrc.read(netrcfile)[hostname]
	filepaths = []
	Net::SFTP.start(hostname, username, :password => password) do |sftp|
		sftp.dir.entries(remotepath).each do |file|
			filepaths << File.join(remotepath, file.name) unless file.directory?
		end
	end

	uris = buildURIsforfiles(filepaths, httpfolderurl, netrcfile)

	items = []
	uris.each do |uri|
		items << PodcastItem.new.constructitemforfileURI(uri)
	end

	return items	
end

def buildURIsforfiles(filepaths, httpfolderurl, netrcfile = nil)
	folderURI = parseURL(httpfolderurl, netrcfile)
	uris	= []
	filepaths.each do |filepath|
		escaped = escapexmlurl(File.basename(filepath))
		uris << URI.join(folderURI, escaped)
	end
	return uris 
end

def parsemedialist()
	items = []
	lines = open(MediaListPath).read.split("\n").map(&:strip)
	lines.each do |line|
		items << line.split("||", 2)
	end
	return items
end

def md5(string)
	md5 = Digest::MD5.new()
	return md5.update(string).hexdigest
end

def savetocache(string, data)
	file = open(File.join(CachePath, md5(string)), "w")
	file.write(data)
	file.close()
end

def loadfromcache(string)
	file = File.join(CachePath, md5(string))
	if File.exists?(file)
		return open(file).read().strip()
	end

	return nil
end
	
	
