# PersonalPodcastServer

A library for media servers to sync content not ordinarily available via podcast and generate RSS XML files to serve their content to podcast clients.

## Current Project Status
This is a personal project of mine, and as it exists now it's a Ruby library and a small set of scripts to help people make their media servers more useful on a day-to-day basis. This is not a turn-key solution. It does require configuration via writing Ruby code. However, as the target audience for this is people who run their own media servers on the internet I think that's probably alright for now. I plan to make example scripts people can work from as the design solidifies.

As this is still a new project I have been updating it quite frequently to expand it with features I need. The code is still not formatted the way I want it due to this growing organically out of a throw-away script I had built and then added to over time.

File an issue if you have a feature request, but do know that priority will be given to things in my personal life and features I need first. I will try to respond to requests in a timely fashion.

## Features
 * Sync YouTube channels to a personal podcast feed to watch offline to avoid using up mobile data with streaming.
 * Download anything [YouTube-DL](https://github.com/rg3/youtube-dl) has support for via URL.
 * Easy access to existing media files by replacing regular directory indexes with per-folder podcast feed indexes.
 * Aggregation of remote server folders without mirroring content on the local server through a mix of SFTP and HTTP calls.
 * Aggregation of remote URL's to your personal podcast feed without mirroring content on the local server.
 * Credential caching via .netrc
 * Content metadata caching to avoid spamming remote servers with requests.

## Security Disclaimer
This project's goal is to allow access to media files on a server with less hassle. This means that if your server is insecure it will also allow the general public to also access your media server with the same lack of hassle. 

**This project's goal is not to provide a public-facing podcast feed server.** The imagined use case, and my use case, is a **personal** server that has been adequately passworded and firewalled.

## Dependencies
 * [Ruby 2.1.5+](https://www.ruby-lang.org/)
 * [netrc Ruby gem](https://rubygems.org/gems/netrc/)
 * [YouTube-DL](https://github.com/rg3/youtube-dl)
 * Any web server that can serve files. 
 * The directory index script requires CGI to be configured on the web server.


