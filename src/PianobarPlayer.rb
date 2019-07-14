require 'liquid'
require 'sinatra/base'

require_relative "MyLogger.rb"

class PianobarPlayer < Sinatra::Base
  
  set :public_folder, "#{File.dirname(__FILE__)}/../public"
  
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
  
  PIANOBAR_START_SLEEP = 1.5
  NOWPLAYING_SLEEP = 0.75
  LOCKFILE_SLEEP = 0.25
  
  @@webapp = "player"

  @@is_playing = false
  
  @@show_pianobar_output = true
  
  def initialize(app = nil, params = {})
    
    super(app)
    
    config = params.fetch(:config, false)
    
    @exe = config["executable"]
    @default_station = config["default_station"]
    @username = config["username"]
    @password = config["password"]
        
    $stdout = StringIO.new
      
    @stopped = nil
    start
  end
  
#  def restart
#    stop unless is running
#    start
#  end
    
  def start
    
    #only consider false. nil is okay
    if(@stopped == false)
      MyLogger.instance.warn("PianobarPlayer", "Ignoring start when PianobarPlayer is already started")
      return
    end
    
    MyLogger.instance.info("PianobarPlayer", "Starting PianobarPlayer")
    
    @webdir = File.expand_path( "#{File.dirname(__FILE__)}/../public") 
    MyLogger.instance.info("PianobarPlayer", "Using www dir #{@webdir}")

    @temp_dir = File.expand_path( "#{File.dirname(__FILE__)}/../tmp")
    MyLogger.instance.info("PianobarPlayer", "Using temp dir #{@temp_dir}")

    @pianobar_temp_dir = File.expand_path( "#{@temp_dir}/pianobar" )
    MyLogger.instance.info("PianobarPlayer", "Using pianobar temp dir #{@pianobar_temp_dir}")

    @pianobar_config_file = File.expand_path("#{@pianobar_temp_dir}/config")
    
    @template_dir = File.expand_path( "#{File.dirname(__FILE__)}/../templates")
    MyLogger.instance.info("PianobarPlayer", "Using template dir #{@template_dir}")
    
    @pianobar_config_template = "#{@template_dir}/pianobar.conf.template"
    @pianobar_event_script_template = "#{@template_dir}/eventcmd.sh.template"
    
    
          
    @command_queue = @temp_dir + "/cmd_queue"
      
    @nowplaying_file = @temp_dir + "/nowplaying"
    @nowplaying_lock_file = @temp_dir + "/nowplaying_lock"
    
    @stationlist_file = @temp_dir + "/stationlist"
    @stationlist_lock_file = @temp_dir + "/stationlist_lock"
    
    @eventcmd_executable = @temp_dir + "/eventcmd.sh"
    @playlist_dir = @temp_dir + "/playlist"
    
    @max_playtime = 180
    
    @pid = nil

    Dir.mkdir( @temp_dir) unless Dir.exists?(@temp_dir)
    Dir.mkdir( "#{@temp_dir}/pianobar") unless Dir.exists?("#{@temp_dir}/pianobar")

    raise "Could not create temp dir: #{@temp_dir}" unless Dir.exists?(@temp_dir)
    raise "Could not create pianobar temp dir: #{@temp_dir}" unless Dir.exists?(@temp_dir)

    write_pianobar_config
    write_pianobar_eventcmd
              
    #create fifo ctl file. expected is $HOME/.config/pianobar/ctl but we can handle that later
    File.delete( @command_queue) if File.exists?(@command_queue)
    File.mkfifo( @command_queue ) 
    
    raise "Could not create pianobar fifo" unless File.exists?( @command_queue )
    
    #delete any temp info from previous runs
    File.delete( @nowplaying_file) if File.exists?(@nowplaying_file)
    File.delete( @nowplaying_lock_file) if File.exists?(@nowplaying_lock_file)

    File.delete( @stationlist_file) if File.exists?(@stationlist_file)
    File.delete( @stationlist_lock_file) if File.exists?(@stationlist_lock_file)

    
    MyLogger.instance.info("PianobarPlayer", "Launching pianobar subprocess")
    #start syscall then pause
    @pid = fork do
      
      #if we don't care about pianobar output, this will disable printing it to the console
      if(!@@show_pianobar_output)
        File.open("/dev/null", 'w') do |io|
          $stdout.reopen(io)
          $stderr.reopen(io)
        end
      end
      
      #dir needs to be full path of dir containing pianobar/config
      #pianobar hardcodes the config file to ~/.config/pianobar/config. 
      exec "XDG_CONFIG_HOME=#{@temp_dir} #{@exe} "# << ' &> /dev/null' 
    end
    
    raise "Could not fork pianobar proceess" unless @pid
    
    MyLogger.instance.info("PianobarPlayer", "Got pianobar pid: #{@pid}")

    #buy time for pianobar to startup
    sleep(PIANOBAR_START_SLEEP)
    
    #TODO: if pianobar launches with a botched config it will just hang
    #maybe check stdout for clues
    pause
    
    #possible we check here that the last line looks something like '#   -00:38/04:22'
    #then redirect stdout/err to /dev/null
    
    #should timeout the pause. if pianobar launches and can't find the config, it'll just hang
    #check for any writes to the command queue
    #MyLogger.instance.info("PianobarPlayer",  "STDOUT read: #{$stdout.string}")
    
    
    #fork max time countdown thread. reset timer on user action
 
    #TODO: test this on a few setups
    #vvvvv handled by 'volume' directive in eventcmd.sh   
#    #boost the default volume
#    7.times do 
#      pianobar_command(PIANOBAR_KEYS["vol_up_key"])
#    end
    @stopped = false
    
    MyLogger.instance.info("PianobarPlayer", "Startup completed" )
  end
  
  def stop
    
    MyLogger.instance.info("PianobarPlayer", "Stopping PianobarPlayer")
    
    #kill pianobar if it's already running
    #can't kill all pianobar processes, another user may be using their own pianobar process
    if(@pid)
      pianobar_command(PIANOBAR_KEYS["quit_key"])
      sleep(2)
      
      #TODO: verify pianobar process tied to pid is dead 
      @pid = nil
      @stopped = true
    end
      
  end
  
  def write_pianobar_config
    
    MyLogger.instance.info("PianobarPlayer", "Writing pianobar config to #{@pianobar_config_file} using template #{@pianobar_config_template}")
    
    #load template, set value hash, render template, write to location
    
    config = ""
    
    #TODO: use template dir variable
    File.open(@pianobar_config_template, "r") do |f|
      f.each_line do |line|
        config += line
      end
    end
    
    template = Liquid::Template.parse(config)
    
    config_params = PIANOBAR_KEYS.clone
    config_params["username"] = @username
      
    #TODO: use cipher for password
    config_params["password"] = @password
        
    config_params["command_queue"] = @command_queue
    config_params["eventcmd_executable"] = @eventcmd_executable
    config_params["default_station"] = @default_station
          
    rendered_config = template.render(config_params)
    
    File.write( @pianobar_config_file, rendered_config )
    
    MyLogger.instance.info("PianobarPlayer", "Pianobar config written")
  
  end
  
  def write_pianobar_eventcmd
    #load template, set value hash, render template, write to location
      
    MyLogger.instance.info("PianobarPlayer", "Writing pianobar event script to #{@eventcmd_executable} using template #{@pianobar_event_script_template}")

    script = ""
    
    File.open(@pianobar_event_script_template, "r") do |f|
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
    
    raise "Could not create event script at #{@eventcmd_executable}" unless File.exists?(@eventcmd_executable)
    
    File.chmod(0755, @eventcmd_executable) unless File.executable?(@eventcmd_executable)
    
    #already checked for file existence a few lines up
    raise "Could make event script executable at #{@eventcmd_executable}" unless File.executable?(@eventcmd_executable)
    
    MyLogger.instance.info("PianobarPlayer", "Pianobar event script written")
  end
  
  ####################
  #pianobar api api
  
  def pianobar_command(input)
    
    #single character for most
    #s123 for station change
    input = input[0..5]
    
    if(input =~ /[a-zA-Z\+\-\^\(\)]/)
      MyLogger.instance.info("PianobarPlayer", "Received pianobar command #{input}")
      
      #command_queue is a named pipe
      retval = system("echo \"#{input}\" > #{@command_queue} ")
      
      if(!retval)
        MyLogger.instance.warn("PianobarPlayer", "Writing command #{input} to pipe has failed")
      end
    else
      MyLogger.instance.warn("PianobarPlayer", "Ignoring invalid pianobar command")
    end
    
    #MyLogger.instance.info("PianobarPlayer",  "STDOUT read: #{$stdout.string}")
  end
    
  def pianobar_command_sync(input)
    mod_time = File.mtime(@nowplaying_file)

    pianobar_command(input)
    
    #sleep? pianobar may take time to get the next song
    while(File.mtime(@nowplaying_file) == mod_time)
      MyLogger.instance.debug("PianobarPlayer", "sleeping, waiting for nowplaying update" )
      sleep(NOWPLAYING_SLEEP) 
    end
  end
      
  def get_stations 
    
    retval = "{}"
    
    if(File.exists?(@stationlist_file))
      
      #TODO: check last write date
      
      #check for lockfile first
      while(File.exists?( @stationlist_lock_file) )
        MyLogger.instance.warn("PianobarPlayer", "stations file being written to. waiting for lock file to be removed." )
        sleep(LOCKFILE_SLEEP)
      end
      
      begin        
        #occasionally the nowplaying file contains incomplete json
        #TODO: sanitize file read before json parse
        stations_json = JSON.parse(File.read(@stationlist_file))
        retval = stations_json.to_json
      rescue JSON::ParserError => e
        MyLogger.instance.warn("PianobarPlayer", "Error parsing stations file #{@stationlist_file}: #{e}" )
      end
    else
      MyLogger.instance.warn("PianobarPlayer", "stations file does not exist #{@stationlist_file}" )
    end
    
    return retval
    
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
    retval = "{}"
    
    if(File.exists?(@nowplaying_file))
      
      #TODO: check last write date

      #check for lockfile first
      while(File.exists?( @nowplaying_lock_file) )
        MyLogger.instance.warn("PianobarPlayer", "nowplaying file being written to. waiting for lock file to be removed." )
        sleep(LOCKFILE_SLEEP)
      end
      
      begin        
        #occasionally the nowplaying file contains incomplete or bad json
        #TODO: sanitize file read before json parse
        song_info_json = JSON.parse(File.read(@nowplaying_file))
        song_info_json["song"]["is_playing"] = @@is_playing
        retval = song_info_json.to_json
      rescue JSON::ParserError => e
        MyLogger.instance.warn("PianobarPlayer", "Error parsing nowplaying file #{@nowplaying_file}: #{e}" )
      end
    else
      MyLogger.instance.warn("PianobarPlayer", "nowplaying file does not exist #{@nowplaying_file}" )
    end
    
    return retval
  end
    
  def change_station(station)
    pianobar_command_sync("s#{station}")
    
    pause unless @@is_playing
  end
    
  #####################
  #web endpoints
  
  get "/#{@@webapp}" do
    
    #ui bound with web requests to manipulate fifo on fs
    
    return File.read("#{@webdir}/index.html")
  end
  
  get "/" do
    redirect "/#{@@webapp}"
  end
  
  get "/#{@@webapp}/" do
    redirect "/#{@@webapp}"
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
    
    #redirect to the player
    redirect "/#{@@webapp}"
  end  
  
  get "/#{@@webapp}/start" do
    #calling start in this manner assumes no changes to the PianobarPlayer config. for those the app needs to be restarted
    start
    
    #redirect to the player
    redirect "/#{@@webapp}"
  end  
  
  get "/#{@@webapp}/quit" do
    stop
    
    MyLogger.instance.info("PianobarPlayer","Pianobar Player exiting")
    
    Process.kill('TERM', Process.pid)
    
    return "<html><body><b>Thanks for coming, please tip your server</b><br><a href=\"/player\">Return to player</a></body></html>"
  end  
  
  get "/#{@@webapp}/song_info" do
    song_info    
  end  
  
  get "/#{@@webapp}/getstations" do
    get_stations    
  end
  
  get "/#{@@webapp}/playstation" do
    #station should be the index of the station list- a number something like 0-100
    
    #support a 10000-length station list as a max
    new_station = params[:station][0..5]
    
#    if(params[:station].size > 5 )
#      new_station = params[:station][0..5]
#    else
#      new_station = params[:station]
#    end
      
    if(new_station =~ /\d+/)
      
      MyLogger.instance.info("PianobarPlayer","Changing pianobar station to #{new_station}")
      
      change_station(new_station)
    else
      MyLogger.instance.warn("PianobarPlayer","Ignoring invalid station change")

    end
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