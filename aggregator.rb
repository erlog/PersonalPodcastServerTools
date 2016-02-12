require_relative 'podcastgeneratorlib'

def handle_media_list(media_list_path)
    parsed_lines = parse_media_list(media_list_path)

    #grab settings
    settings = {}
    parsed_lines.each do |type, arguments, setting|
        settings[arguments[0].downcase] = setting unless type != "setting"
    end

    #sync YouTube and build items
	items = []
	parsed_lines.each do |type, arguments, path|
		case type
		when "fileurl"
			uri = parse_url(path)
			items << Podcast.construct_item_from_uri(uri)

		when "youtubeplaylistsubscription"
			format, url = arguments[0], path
			sync_youtube_playlist(url, settings["mediafolder"], format)

		when "youtubedl"
			format, url = arguments[0], path
			download_youtube_video(url, settings["mediafolder"], format)

		when "remotedirectory"
			items += index_remote_directory(path, settings["netrcfilepath"])

        when "setting"
            next

		else
			puts "No handler for #{type}"
		end
	end

    #add all the downloaded YouTube videos, etc. to the podcast feed
	items += index_local_directory( settings["mediafolder"],
                                    settings["mediafolderurl"],
                                    settings["netrcfilepath"] )

    podcast = Podcast.new( settings["rssfileurl"],
                            settings["title"],
                            settings["description"] )

    podcast.items = items
    podcast.write(settings["rssfilepath"])
end

def parse_media_list(media_list_path)
	lines = open(media_list_path).read.split("\n").map(&:strip)

	items = []
	lines.each do |line|
        next if (line[0] == "#" or line.empty?)
		arguments = line.split("||")
		type, path = arguments.slice!(0), arguments.slice!(-1)
		items << [type.downcase, arguments, path]
	end

	return items
end

def sync_youtube_playlist(url, downloadfolderpath, formatcode)
	downloadfolderpath += "/" unless downloadfolderpath[-1] == "/"
	command = "youtube-dl "
	command += "--max-downloads 10 "
	command += "--playlist-end 10 "
	command += "--youtube-skip-dash-manifest "
	command += "-f #{formatcode} " if formatcode
	command += "--dateafter today-2days "
	command += "-o \"#{downloadfolderpath}%(title)s-%(id)s.%(ext)s\" "
	command += "\"#{url}\""
	return system(command)
end

def download_youtube_video(url, downloadfolderpath, formatcode)
	downloadfolderpath += "/" unless downloadfolderpath[-1] == "/"
	command = "youtube-dl "
	command += "--youtube-skip-dash-manifest "
	command += "-f #{formatcode} " if formatcode
	command += "-o #{downloadfolderpath}\"%(title)s-%(id)s.%(ext)s\" "
	command += "\"#{url}\""
	return system(command)
end


def index_local_directory(localpath, httpfolderurl, netrcfile = nil)
    puts "Indexing #{localpath}"
	filepaths = []

	Dir::entries(localpath).each do |entry|
		filepath = File.join(localpath, entry)
		if File.ftype(filepath) == "file"
			filepaths << filepath
		end
	end

	return build_items_for_files(filepaths, httpfolderurl, netrcfile)
end

def build_items_for_files(filepaths, httpfolderurl, netrcfile = nil)
    httpfolderurl += "/" unless httpfolderurl[-1] == "/"
	folderURI = parse_url(httpfolderurl, netrcfile)

	uris = []
	filepaths.each do |filepath|
        filepath = "/" + filepath unless filepath[0] == "/"
		uris << parse_url(join_url(folderURI, File.basename(filepath)))
	end

	items = []
	uris.each do |uri|
		items << Podcast.construct_item_from_uri(uri)
	end

	return items
end

def index_remote_directory(http_folder_url, netrcfile = nil)
    folder_uri = parse_url(http_folder_url, netrcfile)
    uris = list_downloadable_uris(folder_uri)

	items = []
	uris.each do |uri|
		items << Podcast.construct_item_from_uri(uri)
	end

	return items
end

if __FILE__ == $0
    ARGV.each do |path|
        handle_media_list(path)
    end
end
