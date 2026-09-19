# A CGI response body plus the two things a CGI header needs: the
# content type (Fossil renders `text/x-markdown` inside its own skin,
# with its own CSP and nonce) and an HTTP status, present in the header
# only when it is not the default 200.
module CrystalRobots::Web
  struct Response
    getter body : String
    getter content_type : String
    getter status : Int32

    def initialize(@body : String, @content_type = "text/x-markdown", @status = 200)
    end
  end
end
