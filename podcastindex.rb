#!/usr/bin/env ruby
require 'cgi'
cgi = CGI.new

puts cgi.header
puts "<html><body>%s</body></html>" % ENV["REQUEST_URI"] + " " + ENV["DOCUMENT_ROOT"] 

