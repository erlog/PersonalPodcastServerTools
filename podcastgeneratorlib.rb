require 'time'
require 'shellwords'
require 'uri'
require 'cgi'
require 'net/http'
require 'net/sftp'
require 'mime/types'
require 'openssl'

MIMETypeCommand = "file --mime-type "

class Podcast
	def initialize(rssurl, title, description)
		@items = []
		@rssur = rssurl
		@title = title
		@description = description
	end
	
	attr_accessor :items

	def generateheader()
		header = ['<?xml version="1.0" encoding="UTF-8"?>']
		header << '<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">'
		header << '<channel>'
		header << "<atom:link href=\"%s\" rel=\"self\" type=\"application/rss+xml\"/>" % RSSURL
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

	def constructitemforfileURL(fileurl, username = nil, password = nil)
		uri = URI(escapexmlurl(fileurl))		
		uri.user = escapexmlurl(username) if username
		uri.password = escapexmlurl(password) if password

		http = Net::HTTP.new(uri.host, uri.port)

		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end
		
		request = Net::HTTP::Head.new(uri.request_uri)
		request.basic_auth(username, password) if username
		response = http.request(request)

		@title = fileurl.split("/")[-1] #this is a bad idea
		@url = uri 
		@pubdate = DateTime.httpdate(response["last-modified"]) 
		@filesize = response["content-length"]
		@mimetype = response["content-type"] 
		return self
	end

	def constructitemforfile(localfilepath, httpfolderurl)
		filename = localfilepath.split(File::SEPARATOR)[-1]
		escapedpath = Shellwords.escape(localfilepath)

		@title = filename
		@url = escapexmlurl(urljoin([httpfolderurl, filename]))
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
	url = URI.escape(url)
	url = url.gsub("&", "%26").gsub("'", "%27")
	return url
end

def xmlparamaterize(paramatername, string)
	return "%s=\"%s\"" % [paramatername, string]
end

def outtomedialist(lines)
	medialistfile = open(MediaListPath, "w")
	lines = [lines] if lines.is_a?(String)
	lines.each do |line|
		medialistfile << line + "\n"
	end
	medialistfile.close()
end

def pathjoin(elements)
	return elements.join(File::SEPARATOR)
end

def urljoin(elements)
	return elements.join("/")
end

def indexlocaldirectory(localpath, httpfolderurl)
	items = []
	Dir::entries(localpath).each do |entry|
		filepath = pathjoin([localpath, entry])
		if File.ftype(filepath) == "file"
			items << PodcastItem.new.constructitemforfile(filepath, httpfolderurl)	
		end
	end
	return items
end

def indexremotedirectory(hostname, folderpath, httpfolderurl, username, password)
	podcastitems = []
	Net::SFTP.start(hostname, username, :password => password) do |sftp|
		sftp.dir.entries(folderpath).each do |file|
			if !file.directory?
				fileurl = urljoin([httpfolderurl, file.name])
				podcastitems << PodcastItem.new.constructitemforfileURL(fileurl,
													 username, password) 
			end
		end
	end
	return podcastitems
end

def parsemedialist()
	items = []
	lines = open(MediaListPath).read.split("\n").map(&:strip)
	lines.each do |line|
		items << line.split("||", 2)
	end
	return items
end	
