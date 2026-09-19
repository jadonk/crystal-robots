require "uri"
require "./app"

# Adapts the CGI protocol Fossil's `serverext.wiki` extension mechanism
# uses (https://fossil-scm.org/home/doc/trunk/www/serverext.wiki) to
# `Web::App`: read the standard CGI environment variables and, for a
# POST, the request body from stdin; write a `Status:`/`Content-Type:`
# header followed by the body to stdout. Fossil sets `FOSSIL_USER` and
# `FOSSIL_CAPABILITIES` itself, so this app never handles credentials.
module CrystalRobots::Web::CGI
  def self.run : Nil
    method = ENV["REQUEST_METHOD"]? || "GET"
    body = method == "POST" ? read_body : ""
    params = parse_form(ENV["QUERY_STRING"]? || "")
    params.merge!(parse_form(body)) if method == "POST"

    request = Request.new(
      method: method,
      path: ENV["PATH_INFO"]? || "/",
      params: params,
      script_name: ENV["SCRIPT_NAME"]? || "",
      user: ENV["FOSSIL_USER"]?,
      capabilities: ENV["FOSSIL_CAPABILITIES"]? || "",
      body: body,
    )
    write(App.handle(request))
  end

  private def self.read_body : String
    length = ENV["CONTENT_LENGTH"]?.try(&.to_i?) || 0
    return "" if length <= 0
    buffer = Bytes.new(length)
    STDIN.read_fully(buffer)
    String.new(buffer)
  end

  private def self.parse_form(encoded : String) : Hash(String, String)
    params = {} of String => String
    encoded.split('&').each do |pair|
      next if pair.empty?
      key, _, value = pair.partition('=')
      params[URI.decode_www_form(key)] = URI.decode_www_form(value)
    end
    params
  end

  private def self.write(response : Response) : Nil
    STDOUT.print "Status: #{response.status}\r\n" if response.status != 200
    STDOUT.print "Content-Type: #{response.content_type}\r\n\r\n"
    STDOUT.print response.body
  end
end
