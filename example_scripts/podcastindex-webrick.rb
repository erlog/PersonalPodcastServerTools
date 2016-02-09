#!/usr/bin/env ruby
require 'webrick'
require_relative '../aggregator.rb'

DocumentRoot = File.expand_path("~/files")
NetRCFilePath = File.expand_path("~/.netrc")
ServerURL = ARGV[0]
ListenPort = ARGV[1].to_i

class PodcastIndex < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(request, response)
    response.status = 200
    response['Content-Type'] = 'application/xml'

    rss_uri = ServerURL
    server_uri = Addressable::URI.parse(ServerURL)
    folder_uri = Addressable::URI.parse(join_url(ServerURL, request.path))
    title = folder_uri.path

    description = "Index of %s on %s" % [folder_uri.path, folder_uri.host]
    local_path = File.join(DocumentRoot, request.path)

    if !Dir.exists?(local_path)
        raise WEBrick::HTTPStatus::NotFound, "'#{request.path}' not found."
    end

    podcast = Podcast.new(rss_uri, title, description)
    podcast.items = index_local_directory(local_path, folder_uri.to_s, NetRCFilePath)
    podcast.items.sort_by!(&:pubDate).reverse!

    response.body = podcast.to_s
  end
end

server = WEBrick::HTTPServer.new( :BindAddress => "127.0.0.1",
                                    :Port => ListenPort,
                                    :DocumentRoot => DocumentRoot )
server.mount('/', PodcastIndex)
trap("INT") { server.shutdown }
server.start
