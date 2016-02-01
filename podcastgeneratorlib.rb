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
		header << bracketizeXML("link", @rssurl)
		header << bracketizeXML("title", @title)
		header << bracketizeXML("description", @description)
		return header.join("\n")
	end

	def getXML()
		itemsxml = [] 

		@items.each do |item|
			itemsxml << item.getXML
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
	
	def getXML()
		lines = ['<item>']
		lines << bracketizeXML('title', CGI.escapeHTML(@title)) 
		lines << bracketizeXML('link', @url)
		lines << "<guid isPermaLink=\"false\">%s</guid>" % @url
		lines << bracketizeXML('pubDate', @pubdate.httpdate)
		lines << "<enclosure%s%s%s/>" % [ parameterizeXML(" url", @url), 
								parameterizeXML(" type", @mimetype),
								parameterizeXML(" length", @filesize) ] 
		lines << '</item>'
		return lines.join("\n") 
	end

	def constructitemforfileURI(uri)
		cached = loadfromcache(uri.to_s)
		if cached
			puts ["Using cached: ", uri.path].join
			parseditem = constructitemfromXML(cached) 
			return parseditem unless !parseditem
		end	

		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end
		
		request = Net::HTTP::Head.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(unescapeXMLURL(uri.user), 
						unescapeXMLURL(uri.password)) 
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
		
		savetocache(uri.to_s, getXML)
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

	def constructitemfromXML(xmlstring)
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

def syncYouTubePlaylist(url)
	command = "youtube-dl "\
			"--max-downloads 10 "\
			"--playlist-end 10 "\
			"--youtube-skip-dash-manifest "\
			" --date today "\
			"\"%s\"" % url
	return !system(command)
end

def bracketizeXML(tagname, content)
	return "<%s>%s</%s>" % [tagname, content, tagname]
end

def escapeXMLURL(url)
	url = URI.escape(url.to_s)
	url = url.gsub("&", "%26").gsub("'", "%27")
	return url
end

def unescapeXMLURL(url)
	url = URI.unescape(url)
	url = url.gsub("%26", "&").gsub("%27", "'")
	return url
end

def parseURL(url, netrcfile = nil)
	uri = URI(escapeXMLURL(url))
	if netrcfile
		credentials = Netrc.read(netrcfile)[uri.host]
		uri.user = escapeXMLURL(credentials[0])
		uri.password = escapeXMLURL(credentials[1])
	end
	return uri
end

def parameterizeXML(paramatername, string)
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
		escaped = escapeXMLURL(File.basename(filepath))
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
	
	
