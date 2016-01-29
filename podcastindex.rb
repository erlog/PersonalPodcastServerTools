#!/usr/bin/env ruby
require_relative 'podcastgeneratorlib'
require 'uri'

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
localpath = pathjoin([ENV["DOCUMENT_ROOT"], ENV["REQUEST_URI"]])

puts "Content-type: application/xml\n\n"
podcast.items = indexlocaldirectory(localpath, rssuri)
puts podcast.getxml

