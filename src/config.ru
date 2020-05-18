require 'json'
require_relative './PianobarPlayer.rb'

at_exit do
  puts 'Application shutting down'
  exit 0
end

###########################

puts "Starting up..."

#puts Rack::Server.options

config_file = "#{File.dirname(__FILE__)}/../conf/config.json"

abort("Couldn't find config file #{config_file}" ) unless File.exist?(config_file)

puts "Loading from config file #{config_file}"

parsed_config = JSON.parse(File.read(config_file))

puts "Read config file."

puts "Loading PianobarPlayer"
use PianobarPlayer, config: parsed_config

puts "Running PianobarPlayer\n====================="
run Sinatra::Application
