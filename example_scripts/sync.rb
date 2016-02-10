require_relative '/var/www/personalpodcast/aggregator.rb'

#Path to the list of sources to aggregate
MediaListPaths = ["/var/www/html/podcast/medialist.txt"]

MediaListPaths.each do |path|
    handle_media_list(path)
end
