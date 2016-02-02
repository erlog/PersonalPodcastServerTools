#!/usr/bin/env ruby
require_relative 'podcastgeneratorlib'

#For if you want a username/password inlined into the podcast URL's
NetRCFilePath = "/etc/apache2/.netrc"

def get_full_uri()
	uri = URI("http://blank.blank")
	uri.host = ENV["SERVER_NAME"]
	uri.path = ENV["REQUEST_URI"]
	uri.scheme = ENV["REQUEST_SCHEME"]
	return uri
end

rss_uri = get_full_uri()
title = rss_uri.path
description = "Index of %s on %s" % [rss_uri.path, rss_uri.host]
local_path = File.join(ENV["DOCUMENT_ROOT"], ENV["REQUEST_URI"])

podcast = Podcast.new(rss_uri, title, description)
podcast.items = index_local_directory(local_path, rss_uri, NetRCFilePath)
podcast.items.sort_by!(&:pubdate).reverse!

puts "Content-type: application/xml\n\n"
puts podcast.get_xml

