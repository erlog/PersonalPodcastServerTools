#!/usr/bin/env ruby
require 'cgi'
puts "Content-type: text/html\n\n"

if ENV["REQUEST_METHOD"] == "POST"
	cgi = CGI.new
	medialist = open("/var/www/html/podcast/medialist.txt", "w")
	medialist.write(cgi.params["medialist"][0])
	medialist.close
end

medialist = open("/var/www/html/podcast/medialist.txt").read()
puts '<html><head><title>Podcast Editor</title></head>
<body>
   <FORM value="medialist" action="%s" method="post">
	  <P><textarea 
		 style="width:80%%;height:80%%;resize:both;"
		 name="medialist">%s</textarea></br>
		<INPUT type="submit" value="Save">
	  </P>
   </FORM>
</body>
</html>' % [ENV["SCRIPT_NAME"], medialist]
medialist.close
