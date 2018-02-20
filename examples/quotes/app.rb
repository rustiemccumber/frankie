require_relative '../../frankie'
require 'yaml'

use Rack::Session::Cookie, :key => 'rack.session', :secret => "secret"

get "/" do
  redirect "/quotes"
end

get "/quotes" do
  @quotes = YAML.load(File.read("./data/quotes.yml"))
  erb :index
end

get "/quotes/new" do
  erb :new_quote
end

def insert(author, quote, quotes)
  next_id = quotes['next_id']
  quotes[next_id] = { "author" => author, "quote" => quote }
  quotes['next_id'] += 1
end

post "/quotes" do
  author, quote = params['author'], params['quote']
  quotes = YAML.load(File.read("./data/quotes.yml"))
  insert(author, quote, quotes)
  File.open("./data/quotes.yml","w") { |file| file.write(quotes.to_yaml) }
  session[:message] = 'The quote has been added.'
  redirect "/quotes"
end

get "/set_value" do
  session[:msg] = 'new message'
  session[:msg]
end

get "/get_value" do
  session[:msg]
end
