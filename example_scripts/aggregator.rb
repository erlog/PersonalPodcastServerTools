require_relative '../podcastgeneratorlib'

MediaListPath = "/var/www/html/podcast/medialist.txt"
MediaFolder = "/var/www/html/podcast/media"
MediaFolderURL = "https://mediaserver.com/podcast/media"
RSSFilePath= "/var/www/html/podcast/podcast.xml"
RSSFileURL = "https://mediaserver.com/podcast/podcast.xml"
Title = "Media Server Content Podcast"
Description = "Media list content."
NetRCFilePath = File.expand_path("~/.netrc")
RemoteServerSettings = {
	"myremote" => ["remoteserver.com", "https://remoteserver.com/files"] }


podcast = Podcast.new(RSSFileURL, Title, Description)
podcast.items = handle_media_list(MediaListPath,
							MediaFolder,
							MediaFolderURL,
							RemoteServerSettings,
							NetRCFilePath)
podcast.items.sort_by!(&:title)
open(RSSFilePath, "w").write(podcast.get_xml)

