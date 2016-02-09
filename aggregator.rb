require_relative 'podcastgeneratorlib'
require 'cgi'
require 'net/sftp'
require 'netrc'

def handle_media_list(media_list_path, media_folder, media_folder_url,
								server_settings, netrc_file_path)
	items = []
	parse_media_list(media_list_path).each do |type, arguments, path|
		case type
		when "fileurl"
			uri = parse_url(path)
			items << Podcast.construct_item_from_uri(uri)

		when "youtubeplaylistsubscription"
			format, url = arguments[0], path
			sync_youtube_playlist(url, media_folder, format)

		when "youtubedl"
			format, url = arguments[0], path
			download_youtube_video(url, media_folder, format)

		when "remoteserver"
			settings = server_settings[arguments[0].downcase]
			folder_url = [settings[1], path].join("/")
			hostname = settings[0]
			items += index_remote_directory(hostname, path,
								folder_url, netrc_file_path)
		else
			puts "No handler for #{type}"
		end
	end

	items += index_local_directory(media_folder, media_folder_url,
												netrc_file_path)
	return items
end

def parse_media_list(media_list_path)
	lines = open(media_list_path).read.split("\n").map(&:strip)

	items = []
	lines.each do |line|
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
	filepaths = []

	Dir::entries(localpath).each do |entry|
		filepath = File.join(localpath, entry)
		if File.ftype(filepath) == "file"
			filepaths << filepath
		end
	end

	return build_items_for_files(filepaths, httpfolderurl, netrcfile)
end

def index_remote_directory(hostname, remotepath, httpfolderurl, netrcfile = nil)
	username, password = Netrc.read(netrcfile)[hostname]
	filepaths = []
	Net::SFTP.start(hostname, username, :password => password) do |sftp|
		sftp.dir.entries(remotepath).each do |file|
			filepaths << File.join(remotepath, file.name) unless file.directory?
		end
	end

	return build_items_for_files(filepaths, httpfolderurl, netrcfile)
end

def build_items_for_files(filepaths, httpfolderurl, netrcfile = nil)
    httpfolderurl += "/" unless httpfolderurl[-1] == "/"
	folderURI = parse_url(httpfolderurl, netrcfile)

	uris	= []
	filepaths.each do |filepath|
        filepath = "/" + filepath unless filepath[0] == "/"
        escaped = escape_for_url(File.basename(filepath))
		uris << Addressable::URI.join(folderURI, escaped)
	end

	items = []
	uris.each do |uri|
		items << Podcast.construct_item_from_uri(uri)
	end

	return items
end

def parse_url(url, netrcfile = nil)
	uri = Addressable::URI.parse(url)

	if netrcfile and File.exists?(netrcfile)
		credentials = Netrc.read(netrcfile)[uri.host]
		uri.user = escape_for_url(credentials[0])
		uri.password = escape_for_url(credentials[1])
	end
	return uri
end

def escape_url(url)
    url = Addressable::URI.encode(url.to_s)
    return url
end

def escape_for_url(string)
    string = Addressable::URI.encode(string)
    return string
end
