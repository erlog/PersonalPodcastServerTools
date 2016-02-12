require 'net/http'
require 'openssl'
require 'addressable/uri'
require 'tmpdir'
require 'netrc'
require 'nokogiri'

#cron doesn't fill this value by default
ENV["USER"] = `whoami` unless ENV["USER"]

#Initialize cache
CachePath = File.join(Dir.tmpdir, "podcastgenerator-#{ENV["USER"]}")
Dir.mkdir(CachePath) unless Dir.exist?(CachePath)

def list_downloadable_uris(page_uri)
    #To-do: make this cache properly
    html = request_http_response(page_uri).body

    uris = []
    Nokogiri::HTML(html).css("a").each do |link|
        file_uri = parse_url(link["href"])
        next if !file_uri

        #check for relative URL
        file_uri = parse_url(join_url(page_uri, file_uri)) unless file_uri.host
        #make sure it's not an html file
        header = request_http_header(file_uri)

        uris << file_uri unless header["content-type"][0..3] == "text"
    end

    return uris
end

def request_http_response(uri)
        #To-do, make these fault tolerant and follow 301's, etc.
		http = Net::HTTP.new(uri.host, uri.port)

		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		request = Net::HTTP::Get.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(Addressable::URI.unencode(uri.user),
                                Addressable::URI.unencode(uri.password))
		end

		return http.request(request)
end

def request_http_header(uri)
		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == "https"
			http.use_ssl = true
			http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		request = Net::HTTP::Head.new(uri.request_uri)
		if uri.userinfo
			request.basic_auth(Addressable::URI.unencode(uri.user),
                                Addressable::URI.unencode(uri.password))
		end

		return http.request(request)
end

def join_url(url_a, url_b)
    combined_uri = Addressable::URI.parse([url_a, url_b].join("/"))
    while combined_uri.path.match("//")
        combined_uri.path = combined_uri.path.sub("//", "/")
    end

    return combined_uri.to_s
end

def parse_url(url, netrcfile = nil)
    url = unencode_url(url)
    uri = Addressable::URI.parse(url)

    if netrcfile and File.exists?(netrcfile)
        credentials = Netrc.read(netrcfile)[uri.host]
        uri.user = credentials[0]
        uri.password = credentials[1]
    end

    uri.port = uri.inferred_port unless uri.port

    return Addressable::URI.encode(uri, Addressable::URI)
end

def encode_url(url)
    return Addressable::URI.encode(unencode_url(url))
end

def unencode_url(string)
    return Addressable::URI.unencode(string)
end

def md5(string)
	return Digest::MD5.new.update(string).hexdigest
end

def save_to_cache(string, data)
	file = open(File.join(CachePath, md5(string)), "w")
	file.write(data)
	file.close()
end

def load_from_cache(string)
	file = File.join(CachePath, md5(string))

    if File.exists?(file)
        return open(file).read().strip()
    else
        return nil
    end
end
