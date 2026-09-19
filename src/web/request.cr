# One CGI request. `path` is Fossil's `PATH_INFO` (everything after the
# extroot script name, so `/` for the overview, `/examples/hello` for an
# example); `script_name` is `SCRIPT_NAME` itself, needed to build links
# that stay correct whether the app is served at `/ext/crystal-robots` or
# under a session preview's `/ext/preview/<session>/...`.
module CrystalRobots::Web
  class Request
    getter method : String
    getter path : String
    getter params : Hash(String, String)
    getter script_name : String
    getter user : String?
    getter capabilities : String
    getter body : String

    def initialize(@method : String, @path : String, @params : Hash(String, String),
                   @script_name : String, @user : String?, @capabilities : String, @body : String = "")
    end

    # A link to `suffix` (starting with `/`) that stays correct under
    # whatever prefix this request was actually served at.
    def link(suffix : String) : String
      "#{script_name}#{suffix}"
    end
  end
end
