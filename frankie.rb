require 'rack'

module Frankie
  class Application
    class << self
      def routes
        @routes
      end

      def route(verb, path, &block)
        @routes ||= {}
        @routes[verb] ||= []
        pattern, keys = compile(path)
        signature = { pattern: pattern, keys: keys, block: block }
        @routes[verb] << signature
        signature
      end

      def get(path, &block)
        route('GET', path, &block)
      end

      def post(path, &block)
        route('POST', path, &block)
      end

      def compile(path)
        segments = path.split('/', -1)
        keys = []

        segments.map! do |segment|
          if segment.start_with?(':')
            keys << segment[1..-1]
            "([^\/]+)"
          else
            segment
          end
        end

        pattern = Regexp.compile("\\A#{segments.join('/')}\\z")
        [pattern, keys]
      end

      def call(env)
        new.call(env)
      end
    end

    def call(env)
      @request = Rack::Request.new(env)
      @response = Rack::Response.new

      invoke { route! }

      @response.finish
    end

    def params
      @request.params
    end

    def invoke
      res = catch(:halt) { yield }
      res = [res] if Integer === res or String === res
      if Array === res and Integer === res.first
        res = res.dup
        @response.status = res.shift
        @response.body = res.pop
        @response.headers.merge!(*res) # why is the splat needed?
      elsif res.respond_to? :each
        @response.body = res
      end
      nil
    end

    def route!
      routes = self.class.routes
      verb = @request.request_method
      path = @request.path_info

      routes[verb].each do |route|
        match = route[:pattern].match(path)
        if match
          params.merge!(route[:keys].zip(match.captures).to_h)
          halt instance_eval(&route[:block])
        end
      end

      not_found
    end

    def redirect(uri)
      if params['HTTP_VERSION'] == 'HTTP/1.1' && params["REQUEST_METHOD"] != 'GET'
        @response.status = 303
      else
        @response.status = 302
      end

      @response.headers['Location'] = uri
      halt
    end

    def halt(response = nil)
      throw :halt, response
    end

    # TODO: I don't think this is how Sinatra does it
    def not_found
      halt [404, {}, ['<h1>404</h1>']]
    end

    def erb(template, path = "./views/#{template}.erb")
      content = File.read(path)
      ERB.new(content).result(binding)
    end
  end

  module Delegator
    def self.delegate(method)
      define_method(method) do |path, &block|
        Application.send(method, path, &block)
      end
    end

    delegate(:get); delegate(:post)
  end

  unless ENV['RACK_ENV'] == 'test'
    at_exit { Rack::Handler::WEBrick.run Frankie::Application, Port: 4567 }
  end
end

extend Frankie::Delegator
