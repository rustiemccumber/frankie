require 'rack'

module Frankie
  module Templates
    def erb(template, path = "./views/#{template}.erb")
      content = File.read(path)
      ERB.new(content).result(binding)
    end
  end

  class Application
    include Templates

    def call(env)
      @request = Rack::Request.new(env)
      @response = Rack::Response.new

      invoke { dispatch! }

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

    def halt(response = nil)
      throw :halt, response
    end

    def dispatch!
      route!
      not_found # Sinatra does error handling here.
    end

    def route!
      routes = self.class.routes

      if routes
        verb = @request.request_method
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
      if @request.request_method == 'GET'
        @response.status = 302
      else
        @response.status = 303
      end

      @response.headers['Location'] = uri
      halt
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
        new.call(env)
      end
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