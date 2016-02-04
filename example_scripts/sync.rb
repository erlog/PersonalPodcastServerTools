require_relative '/var/www/cgi-bin/aggregator.rb'

#Path to the list of sources to aggregate
MediaListPath = "/var/www/html/podcast/medialist.txt"

#Location to save downloaded media on the local server
MediaFolder = "/var/www/html/podcast/media"
MediaFolderURL = "https://mediaserver.tld/podcast/media"

#Location to save the RSS file to
RSSFilePath = "/var/www/html/podcast/podcast.xml"
RSSFileURL = "https://mediaserver.tld/podcast/podcast.xml"

#Podcast channel information
Title = "Media server podcast feed."
Description = "Media list content."

#Setting and credentials to use for remote servers, if applicable
RemoteServerSettings = {
	"myremote" => ["myremote.tld", "https://myremote.tld/files"] }
NetRCFilePath = File.expand_path("~/.netrc")


podcast = Podcast.new(RSSFileURL, Title, Description)
podcast.items = handle_media_list(MediaListPath,
                                    MediaFolder,
                                    MediaFolderURL,
                                    RemoteServerSettings,
                                    NetRCFilePath)

podcast.items.sort_by!(&:title)
podcast.write(RSSFilePath)
