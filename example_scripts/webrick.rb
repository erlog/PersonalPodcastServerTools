#!/usr/bin/env ruby
require 'webrick'
include WEBrick

web_root = "/home/juantwo/files/"
port = 37195
ENV["GEM_HOME"] = Gem.dir
ENV["GEM_PATH"] = Gem.path.join(":")
server = HTTPServer.new( :Port => 37195, :DocumentRoot => web_root)
server.mount('/', HTTPServlet::CGIHandler, 'podcastindex.cgi')
trap("INT") { server.shutdown }
server.start
