require 'logger'
require 'liquid'
require 'sinatra/base'

class PianobarPlayer < Sinatra::Base
  
  set :public_folder, './public'
  
  PIANOBAR_KEYS =
  {
    "love_song_key" => "+",
    "ban_song_key" => "-",
    "song_info_key" => "i",
    "next_song_key" => "n",
    "pause_song_key" => "p",
    "play_song_key" => "P",   #not used by pianobar config for some reason
    "station_change_key" => "s",
    "upcoming_song_key" => "u",
    "vol_down_key" => "(",
    "vol_up_key" => ")",
    "vol_reset_key" => "^",
    "quit_key" => "q"
  }
  
  @@webapp = "player"

  @@is_playing = false
  
  def initialize(app = nil, params = {})
    
    super(app)
    
    config = params.fetch(:config, false)
    
    logfile = config["logfile"] unless !config["logfile"]
    logfile = '../logs/pianobar.log' unless logfile
    FileUtils.mkdir_p File.dirname(logfile) unless File.exists?(logfile)
    
    @exe = config["executable"]
    @default_station = config["default_station"]
    @username = config["username"]
    @password = config["password"]
    
      
    $logger = Logger.new(logfile, 0, 10 * 1024 * 1024) 
      
    #FileUtils.mkdir_p "../tmp/pianobar/config" unless File.exists?("../tmp/pianobar/config")
    @config_file = File.expand_path("../tmp/pianobar/config")
        
    @temp_dir = File.dirname(@config_file)
    @template_dir = "../templates/"
          
    @command_queue = @temp_dir + "/cmd_queue"
    @nowplaying_file = @temp_dir + "/nowplaying"
    @stationlist_file = @temp_dir + "/stationlist"
    @eventcmd_executable = @temp_dir + "/eventcmd.sh"
    @playlist_dir = @temp_dir + "/playlist"
    
    @max_playtime = 180
    
    @pid = nil

    
    #for each user's account
  
    stop
    sleep 3
    
    system("mkdir #{@temp_dir}") unless Dir.exists?(@temp_dir)

    write_pianobar_config
    write_pianobar_eventcmd
    
    raise "Could not read config file" unless File.exists?("#{@config_file}")
    
    #pianobar hardcodes the config file to ~/.config/pianobar/config. create a symlink
#    system("mkdir -p ~/.config/pianobar/")
#    raise "Could not link config file" unless system("ln -fs #{@config_file} #{@pianobar_symlink}")
          
    #create fifo ctl file $HOME/.config/pianobar/ctl
    system("rm #{@command_queue}") if File.exists?("#{@command_queue}")
    system("mkfifo #{@command_queue}") 
    
    raise "Could not create pianobar fifo" unless File.exists?( @command_queue )
    
    puts "Launching pianobar"
    #start syscall then pause
    @pid = fork do
      
      #don't care about pianobar output -> disable printing it to the console
#      File.open("/dev/null", 'w') do |io|
#        $stdout.reopen(io)
#        $stderr.reopen(io)
#      end
      
      exec "XDG_CONFIG_HOME=#{@temp_dir}/../ #{@exe} "# << ' &> /dev/null' 
    end
    
    raise "Could not fork pianobar proceess" unless @pid
    
    #buy time for pianobar to startup
    sleep 1.5
    pause
    
    #should timeout the pause. if pianobar launches and can't find the config, it'll just hang
    #check for any writes to the command queue
    
    #fork max time countdown thread. reset timer on user action
 
    #vvvvv handled by 'volume' directive in eventcmd.sh   
#    #boost the default volume
#    7.times do 
#      pianobar_command(PIANOBAR_KEYS["vol_up_key"])
#    end

  end
  
  def restart
    #start calls stop
    start
  end
    
  def stop
    
    #kill pianobar if it's already running
    if(@pid)
      pianobar_command(PIANOBAR_KEYS["quit_key"])
      sleep 2
      @pid = nil
    end
      
    #can't kill all pianobar processes, another user may be using their own pianobar process
#    stale_pids = `ps -ef |grep pianobar | grep -v grep | awk '{print $2}'`.gsub("\n", " ").chomp!
#    
#    $logger.info("Killing stale pids: #{stale_pids}") unless !stale_pids
#    
#    `kill #{stale_pids}` unless !stale_pids
  end
  
  def write_pianobar_config
    #load template, set value hash, render template, write to location
    
    config = ""
    
    File.open("../templates/pianobar.conf.template", "r") do |f|
      f.each_line do |line|
        config += line
      end
    end
    
    template = Liquid::Template.parse(config)
    
    config_params = PIANOBAR_KEYS.clone
    config_params["username"] = @username
    config_params["password"] = @password  
    config_params["command_queue"] = @command_queue
    config_params["eventcmd_executable"] = @eventcmd_executable
    config_params["default_station"] = @default_station
          
    rendered_config = template.render(config_params)
    
    File.write( @config_file, rendered_config )
  
  end
  
  def write_pianobar_eventcmd
    #load template, set value hash, render template, write to location
      
    script = ""
    
    File.open("../templates/eventcmd.sh.template", "r") do |f|
      f.each_line do |line|
        script += line
      end
    end
    
    template = Liquid::Template.parse(script)
    
    script_params={}
    script_params["now_playing_file"] = @nowplaying_file
    script_params["station_list_file"] = @stationlist_file
    
          
    rendered_script = template.render(script_params)
    
    File.write( @eventcmd_executable, rendered_script )
    system("chmod +x #{@eventcmd_executable}")
  end
  
  def pianobar_command(input)
    $logger.debug("Received pianobar command #{input}")
    system("echo \"#{input}\" > #{@command_queue} ")
  end
    
  def pianobar_command_sync(input)
    mod_time = File.mtime(@nowplaying_file)

    pianobar_command(input)
    
    #sleep? pianobar make take time to get the next song
    while File.mtime(@nowplaying_file) == mod_time
      puts "sleeping, waiting for nowplaying update"
      sleep(0.75) 
    end
  end
      
  def get_stations
    stations = JSON.parse(File.read(@stationlist_file))
      
    return stations.to_json 
  end
  
  def play
    pianobar_command(PIANOBAR_KEYS["play_song_key"])
    
    @@is_playing = true
  end
  
  def pause
    pianobar_command(PIANOBAR_KEYS["pause_song_key"])
    
    @@is_playing = false
  end
    
  def next_song
    pianobar_command_sync(PIANOBAR_KEYS["next_song_key"])
        
    #pretty sure next autoplays. let's prevent that if we're already paused
    pause unless @@is_playing
  end
    
  def ban
    pianobar_command_sync(PIANOBAR_KEYS["ban_song_key"])
      
    #pretty sure ban autoplays. let's prevent that if we're already paused
    pause unless @@is_playing
  end
  
  def upcoming
    pianobar_command(PIANOBAR_KEYS["upcoming_song_key"])
  end
    
  def song_info
    song_info_json = ""
    
    File.open(@nowplaying_file, "r") do |f|
      f.each_line do |line|
        song_info_json += line
      end
    end
    
    puts "Could not read from #{@nowplaying_file}" unless song_info_json
    
    song_info = JSON.parse(song_info_json)
    song_info["song"]["is_playing"] = @@is_playing

    return song_info.to_json
  end
    
  def change_station(station)
    pianobar_command_sync("s#{station}")
    
    pause unless @@is_playing
  end
    
  get "/#{@@webapp}" do
    
    #ui bound with web requests to manipulate fifo on fs
    
     
    return    "<script type=\"text/javascript\" src=\"js/pianobar.js\"></script>\n" <<
        "<script type=\"text/javascript\" src=\"js/jquery-1.11.3.min.js\"></script>\n" <<
        "<script type=\"text/javascript\" src=\"js/jquery-ui-1.11.4.custom/jquery-ui.min.js\"></script>\n" <<
        '<link rel="stylesheet" href="//http://code.jquery.com/ui/1.11.4/themes/redmond/jquery-ui.min.css">' << "\n"<<
          
        #now playing info from nowplaying file
        '<script type="text/javascript">' << "\n" <<
        '$( document ).ready(function() {' << "\n" <<
          '$("#requestResult").show();' <<"\n" <<
          '$("#songinfo").show();' <<"\n" <<
          
          'updatePlayer();' << "\n" <<
          'setInterval(function(){ updatePlayer()},2000);' << "\n" <<
          
          'updateStationList();' << "\n" <<
          'setInterval(function(){ updateStationList()},12000);' << "\n" <<
        '});' << "\n" << '</script>' <<"\n" <<
        
        '<div id="songinfo"></div>' <<"\n"<<
        '<button id="playButton" type="button" onclick=" play(); ">Play</button>' <<"\n"<<
        '<button id="pauseButton" type="button" onclick=" pause(); ">Pause</button>' <<"\n"<<
        '<button id="likeButton" type="button" onclick=" like(); ">:)</button>' <<"\n"<<
        '<button id="banButton" type="button" onclick=" ban(); ">:(</button>' <<"\n"<<
        '<button id="nextButton" type="button" onclick=" next(); ">&#8658;</button>' <<"\n"<<
        '<button id="volupButton" type="button" onclick=" volup(); ">VOL+</button>' <<"\n"<<
        '<button id="voldownButton" type="button" onclick=" voldown(); ">VOL-</button>' <<"\n"<<
        '<button id="volresetButton" type="button" onclick=" volreset(); ">VOL0</button>' <<"\n"<<
        '<div id="stationlist"><br><b>Stations</b><br><select id="stationSelect" onchange="changeStation(this.value);"></select></div>' <<"\n"<<
        '<div id="requestResult"></div>' <<"\n"
  end
  
  get "/#{@@webapp}/play" do  
      play
  end
  
  get "/#{@@webapp}/is_playing" do
      @@is_playing.to_s
  end
  
  get "/#{@@webapp}/pause" do
      pause 
  end  
  
  get "/#{@@webapp}/next" do    
      next_song
  end  
  
  get "/#{@@webapp}/like" do
      pianobar_command(PIANOBAR_KEYS["love_song_key"])
      
      #update the nowplaying file with the new rating, since pianobar wont
  end  
  
  get "/#{@@webapp}/ban" do
    ban
  end  
  
  get "/#{@@webapp}/stop" do
    stop
  end  
  
  get "/#{@@webapp}/song_info" do
    song_info    
  end  
  
  get "/#{@@webapp}/getstations" do
    get_stations    
  end
  
  get "/#{@@webapp}/playstation" do
    new_station = params[:station]
    
    $logger.debug("Changing pianobar station to #{new_station}")
      
    change_station(new_station)
  end    
  
  get "/#{@@webapp}/volup" do
    pianobar_command(PIANOBAR_KEYS["vol_up_key"])
  end
  
  get "/#{@@webapp}/voldown" do
    pianobar_command(PIANOBAR_KEYS["vol_down_key"])
  end    
  
  get "/#{@@webapp}/volreset" do
    pianobar_command(PIANOBAR_KEYS["vol_reset_key"])
  end    
end