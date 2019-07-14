require 'json'
require_relative './PianobarPlayer.rb'

at_exit do
  puts 'Application shutting down'
  exit 0 
end

###########################

puts "Starting up..."

parsed_config = JSON.parse(File.read("#{File.dirname(__FILE__)}/../conf/config.json"))

puts "Read config file."

puts "Loading PianobarPlayer"
use PianobarPlayer, config: parsed_config

puts "Running PianobarPlayer\n====================="
run Sinatra::Application