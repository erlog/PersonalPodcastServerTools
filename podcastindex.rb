#!/usr/bin/env ruby
require_relative 'podcastgeneratorlib'

#For if you want a username/password inlined into the podcast URL's
NetRCFilePath = "/etc/apache2/.netrc"

def getfulluri()
	uri = URI("http://blank.blank")
	uri.host = ENV["SERVER_NAME"]
	uri.path = ENV["REQUEST_URI"]
	uri.scheme = ENV["REQUEST_SCHEME"]
	return uri
end

rssuri = getfulluri() 
title = rssuri.path
description = "Index of %s on %s" % [rssuri.path, rssuri.host]
podcast = Podcast.new(rssuri, title, description)
localpath = File.join(ENV["DOCUMENT_ROOT"], ENV["REQUEST_URI"])

puts "Content-type: application/xml\n\n"
podcast.items = indexlocaldirectory(localpath, rssuri, NetRCFilePath)
puts podcast.getXML

