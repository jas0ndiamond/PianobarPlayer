require 'json'
require_relative './PianobarPlayer.rb'

parsed_config = JSON.parse(File.read("../conf/config.json"))

use PianobarPlayer, config: parsed_config

puts "====================="
run Sinatra::Application