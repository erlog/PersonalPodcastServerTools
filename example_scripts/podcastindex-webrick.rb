#!/usr/bin/env ruby
require 'webrick'
require_relative '../aggregator.rb'

DocumentRoot = File.expand_path("~/")
NetRCFilePath = "/etc/apache2/.netrc"
ServerURL = "http://127.0.0.1:37195"
Port = 37195

class PodcastIndex < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(request, response)
    response.status = 200
    response['Content-Type'] = 'application/xml'

    rss_uri = URI.join(ServerURL, request.path)
    title = rss_uri.path
    description = "Index of %s on %s" % [rss_uri.path, rss_uri.host]
    local_path = File.join(DocumentRoot, request.path)

    if !Dir.exists?(local_path)
        raise WEBrick::HTTPStatus::NotFound, "'#{request.path}' not found."
    end

    podcast = Podcast.new(rss_uri, title, description)
    podcast.items = index_local_directory(local_path, rss_uri.to_s, NetRCFilePath)
    podcast.items.sort_by!(&:pubDate).reverse!

    response.body = podcast.to_s
  end
end

server = WEBrick::HTTPServer.new( :BindAddress => "0.0.0.0",
                                    :Port => Port,
                                    :DocumentRoot => DocumentRoot )
server.mount('/', PodcastIndex)
trap("INT") { server.shutdown }
server.start
