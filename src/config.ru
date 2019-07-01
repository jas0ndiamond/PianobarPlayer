require 'json'
require_relative './PianobarPlayer.rb'

parsed_config = JSON.parse(File.read("#{File.dirname(__FILE__)}/../conf/config.json"))

at_exit do
  puts 'Application shutting down'
  exit 0 
end

use PianobarPlayer, config: parsed_config

puts "====================="
run Sinatra::Application