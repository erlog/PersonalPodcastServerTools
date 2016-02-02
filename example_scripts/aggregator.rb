require_relative 'podcastgeneratorlib'
#This is an example file meant for customization

MediaListPath = "/var/www/html/podcast/medialist.txt"
MediaFolder = "/var/www/html/podcast/media"
OutputPath = "/var/www/html/podcast/podcast.xml"
RSSURL = "https://mediaserver.com/podcast/podcast.xml"
Title = "Media Server Content Podcast" 
NetRCFilePath = File.expand_path("~/.netrc")

podcast = Podcast.new(RSSURL, Title, Title)

parsemedialist().each do |type, argument|
	case type 
		when "fileurl" 
			uri = parseURL(argument)
			podcast.items << PodcastItem.new.constructitemforfileURI(uri)	
		when "youtubeplaylistsubscription"
			syncYouTubePlaylist(argument, MediaFolder)
		when "remoteserver"
			folderurl = ["https://remoteserver.com/files", argument].join("/") 
			folderpath = argument 
			hostname = "remoteserver.com" 
			podcast.items += indexremotedirectory(hostname, folderpath,
								folderurl, NetRCFilePath)
		when "youtubedl"
			downloadYouTubeVideo(argument, MediaFolder, 22)
	end
end

podcast.items.sort_by!(&:title)
open(OutputPath, "w").write(podcast.getXML)

