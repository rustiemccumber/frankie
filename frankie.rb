require 'rack'

module Frankie
  module Templates
    def erb(template, path = "./views/#{template}.erb")
      content = File.read(path)
      ERB.new(content).result(binding)
    end
  end

  class Response < Rack::Response
    def initialize
      super
      headers['Content-Type'] ||= 'text/html'
    end
  end

  class Application
    include Templates

    def call!(env)
      @env = env
      @request = Rack::Request.new(env)
      @response = Response.new

      invoke { dispatch! }

      @response.finish
    end

    def invoke
      res = catch(:halt) { yield }
      res = [res] if Integer === res || String === res
      if Array === res && Integer === res.first
        res = res.dup
        @response.status = res.shift
        unless res.empty?
          @response.body = res.pop
          @response.headers.merge!(*res)
        end
      elsif res.respond_to? :each
        @response.body = res
      end
      nil
    end

    def halt(response = nil)
      throw :halt, response
    end

    def dispatch!
      route!
      not_found
    end

    def route!
      routes = self.class.routes
      verb = @request.request_method

      if routes[verb]
        path = @request.path_info

        routes[verb].each do |route|
          match = route[:pattern].match(path)
          if match
            values = match.captures.to_a
            params.merge!(route[:keys].zip(values).to_h)
            halt instance_eval(&route[:block])
          end
        end
      end
    end

    def not_found
      halt [404, {}, ['<h1>404</h1>']]
    end

    def redirect(uri)
      if @request.get?
        @response.status = 302
      else
        @response.status = 303
      end

      @response.headers['Location'] = uri
      halt
    end

    def params
      @request.params
    end

    def headers
      @response.headers
    end

    def session
      @request.session
    end

    class << self
      def routes
        @routes ||= {}
      end

      def get(path, &block)
        route('GET', path, &block)
      end

      def post(path, &block)
        route('POST', path, &block)
      end

      def route(verb, path, &block)
        routes[verb] ||= []
        pattern, keys = compile(path)
        signature = { pattern: pattern, keys: keys, block: block }
        routes[verb] << signature
        signature
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
        new.call!(env)
      end

      alias new! new

      def new
        instance = new!
        # now we can do additional stuff, like set up middleware
      end


    end
  end

  module Delegator
    def self.delegate(method)
      define_method(method) do |path, &block|
        Application.send(method, path, &block)
      end
    end

    delegate(:get); delegate(:post); delegate(:use)
  end

  unless ENV['RACK_ENV'] == 'test'
    at_exit { Rack::Handler::WEBrick.run Frankie::Application }
  end
end

extend Frankie::Delegator