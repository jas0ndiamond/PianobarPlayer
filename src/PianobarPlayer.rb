require 'liquid'
require 'sinatra/base'

require_relative "MyLogger.rb"

class PianobarPlayer < Sinatra::Base

  set :public_folder, "#{File.dirname(__FILE__)}/../public"

  BE_LOG_HANDLE = "PianobarPlayer"
  API_LOG_HANDLE = "PianobarPlayerAPI"

  PIANOBAR_KEYS =
  {
    "love_song_key" => "+",
    "ban_song_key" => "-",
    "song_info_key" => "i",
    "next_song_key" => "n",
    "pause_song_key" => "p",
    "play_song_key" => "P",   #not used by pianobar config for some reason. TODO: check this again
    "station_change_key" => "s",
    "upcoming_song_key" => "u",
    "vol_down_key" => "(",
    "vol_up_key" => ")",
    "vol_reset_key" => "^",
    "quit_key" => "q"
  }

  PIANOBAR_START_SLEEP = 1.5
  PIANOBAR_STOP_SLEEP = 10
  NOWPLAYING_SLEEP = 0.75
  LOCKFILE_SLEEP = 0.25

  #class variables. if state changes are driven by code executed in the endpoints,
  #they seem to need to be class variables rather than instance variables
  #player_stopped, is_playing seem to not hold on to values if they are
  #instance variables
  @@webapp = "player"
  @@player_stopped = nil
  @@is_playing = nil

  def initialize(app = nil, params = {})

    super(app)

    @application_pid = Process.pid

    config = params.fetch(:config, false)

    @exe = config["executable"]
    @default_station = config["default_station"]
    @username = config["username"]
    @password = config["password"]

    @@is_playing = false
    @@player_stopped = true
    @show_pianobar_output = true

    MyLogger.instance.setLevel(config["logLevel"])

    $stdout = StringIO.new

    #start the player without waiting for ui input. this could be running headless.

    start
  end

  def start

    # only consider false. nil is okay
    if(@@player_stopped == false)
      MyLogger.instance.warn(BE_LOG_HANDLE, "Ignoring start when PianobarPlayer is already started")
      return
    end

    MyLogger.instance.info(BE_LOG_HANDLE, "Starting PianobarPlayer")

    @webdir = File.expand_path( "#{File.dirname(__FILE__)}/../public")
    MyLogger.instance.info(BE_LOG_HANDLE, "Using www dir #{@webdir}")

    @player_page_html = File.read("#{@webdir}/index.html")

    @temp_dir = File.expand_path( "#{File.dirname(__FILE__)}/../tmp")
    MyLogger.instance.info(BE_LOG_HANDLE, "Using temp dir #{@temp_dir}")

    @pianobar_temp_dir = File.expand_path( "#{@temp_dir}/pianobar" )
    MyLogger.instance.info(BE_LOG_HANDLE, "Using pianobar temp dir #{@pianobar_temp_dir}")

    @pianobar_config_file = File.expand_path("#{@pianobar_temp_dir}/config")

    @template_dir = File.expand_path( "#{File.dirname(__FILE__)}/../templates")
    MyLogger.instance.info(BE_LOG_HANDLE, "Using template dir #{@template_dir}")

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

    @pianobar_pid = nil

    abort("Could not find pianobar binary at #{@exe}") unless File.exists?(@exe)

    MyLogger.instance.info(BE_LOG_HANDLE, "Using Pianobar binary at #{@exe}")


    Dir.mkdir( @temp_dir) unless Dir.exist?(@temp_dir)
    Dir.mkdir( "#{@temp_dir}/pianobar") unless Dir.exist?("#{@temp_dir}/pianobar")

    raise "Could not create temp dir: #{@temp_dir}" unless Dir.exist?(@temp_dir)
    raise "Could not create pianobar temp dir: #{@temp_dir}" unless Dir.exist?(@temp_dir)

    write_pianobar_config
    write_pianobar_eventcmd

    #create fifo ctl file. expected is $HOME/.config/pianobar/ctl but we can handle that later
    File.delete( @command_queue) if File.exist?(@command_queue)
    File.mkfifo( @command_queue )

    raise "Could not create pianobar fifo" unless File.exist?( @command_queue )

    #delete any temp info from previous runs
    File.delete( @nowplaying_file) if File.exist?(@nowplaying_file)
    File.delete( @nowplaying_lock_file) if File.exist?(@nowplaying_lock_file)

    File.delete( @stationlist_file) if File.exist?(@stationlist_file)
    File.delete( @stationlist_lock_file) if File.exist?(@stationlist_lock_file)

    pianobar_syscall = "XDG_CONFIG_HOME=#{@temp_dir} #{@exe}"

    MyLogger.instance.info(BE_LOG_HANDLE, "Launching pianobar subprocess: #{pianobar_syscall}")

    #start syscall then pause player
    @pianobar_pid = fork do

      #TODO: switch this over to popen3

      #ughhh
      Process.setsid

      #if we don't care about pianobar output, this will disable printing it to the console
      if(!@show_pianobar_output)
        File.open("/dev/null", 'w') do |io|
          $stdout.reopen(io)
          $stderr.reopen(io)
        end
      end

      #dir needs to be full path of dir containing pianobar/config
      #pianobar hardcodes the config file to ~/.config/pianobar/config.
      exec "#{pianobar_syscall}"# << ' &> /dev/null'

      #@with exec, we'll never get here
      # MyLogger.instance.info(BE_LOG_HANDLE, "Pianobar fork exiting")
      #
      # exit 0;
    end

    raise "Could not fork pianobar proceess" unless @pianobar_pid

    MyLogger.instance.info(BE_LOG_HANDLE, "Got pianobar pid: #{@pianobar_pid}")

    #buy time for pianobar to startup
    sleep(PIANOBAR_START_SLEEP)

    #it may start playing right away
    pause

    #TODO: if pianobar launches with a botched config it will just hang
    #maybe check stdout for clues

    #possible we check here that the last line looks something like '#   -00:38/04:22'
    #then redirect stdout/err to /dev/null

    #should timeout the pause. if pianobar launches and can't find the config, it'll just hang
    #check for any writes to the command queue
    #MyLogger.instance.info(BE_LOG_HANDLE,  "STDOUT read: #{$stdout.string}")


    #fork max time countdown thread. reset timer on user action

    #TODO: test this on a few setups
    #vvvvv handled by 'volume' directive in eventcmd.sh
#    #boost the default volume
#    7.times do
#      pianobar_command(PIANOBAR_KEYS["vol_up_key"])
#    end

    # it's hard to determine if the pianobar/pandora login succeeded
    # however if we get the nowplaying and stationlist files, we can
    # interpret that as a successful login. otherwise kill the pianobar
    # pid and warn the user that the login may be bad or the service
    # may be down

    #TODO: check that nowplaying_file isn't empty

    #check for the new now_playing file
    max_attempts = 10
    attempts = 0
    MyLogger.instance.info(BE_LOG_HANDLE, "Waiting for nowplaying file creation" )
    while( !File.exist?(@nowplaying_file) and attempts < max_attempts )
      attempts += 1
      MyLogger.instance.warn(BE_LOG_HANDLE, "Waiting for nowplaying file creation attempt: #{attempts}" )
      sleep(0.5)
    end

    if(attempts >= max_attempts)
      MyLogger.instance.error(BE_LOG_HANDLE, "Nowplaying file was not created. Check your pianobar config. Exiting." )

      #TODO: maybe try echoing the quit command to the command queue

      stop

      #TODO: necessary to kill this?
      Process.kill('TERM', Process.pid)

      #TODO: proper exception
      raise "Pianobar Startup problem"

    else
      MyLogger.instance.info(BE_LOG_HANDLE, "Nowplaying file found" )

      #if we get now-playing data the player has technically started
      #want to set this as early as possible
      @@player_stopped = false
    end

    attempts = 0
    MyLogger.instance.info(BE_LOG_HANDLE, "Waiting for station list file creation" )
    while( !File.exist?(@stationlist_file) and attempts < max_attempts )
      attempts += 1
      MyLogger.instance.warn(BE_LOG_HANDLE, "Waiting for station list file creation attempt: #{attempts}" )
      sleep(0.5)
    end

    if(attempts >= max_attempts)
      MyLogger.instance.error(BE_LOG_HANDLE, "Station list file was not created. Check your pianobar config. Exiting." )

      stop

      Process.kill('TERM', @pianobar_pid)

      #TODO: proper exception
      raise "Pianobar Startup problem"
    else
      MyLogger.instance.info(BE_LOG_HANDLE, "Station list file found" )
    end





    MyLogger.instance.info(BE_LOG_HANDLE, "Startup completed" )



  end

  def stop

    #only consider true. nil is okay and means false
    if(@@player_stopped == true)
      MyLogger.instance.warn(BE_LOG_HANDLE, "Ignoring stop when PianobarPlayer is already stopped")
      return
    end

    @@player_stopped = true

    MyLogger.instance.info(BE_LOG_HANDLE, "Stopping PianobarPlayer")

    #kill pianobar if it's already running
    #can't kill all pianobar processes, another user may be using their own pianobar process
    if(@pianobar_pid)

      pid_exists_syscall = "ps -ef | grep #{@pianobar_pid} | grep pianobar | grep -v grep"

      #TODO: quit may hang. time this operation out and kill if necessary
      pianobar_command(PIANOBAR_KEYS["quit_key"])

      #buy time for the quit to complete
      #sleep(PIANOBAR_STOP_SLEEP)

      attempts = 0
      max_attempts = 10
      while( `#{pid_exists_syscall}` && attempts < max_attempts )
        MyLogger.instance.debug(BE_LOG_HANDLE, "Pianobar process (#{@pianobar_pid}) still alive. Waiting on quit to complete.")
        attempts += 1
        sleep(1)
      end

      #meed thos or otherwise the pianobar process zombies out. something to do with exec running in a fork
      Process.detach(@pianobar_pid)

      #a new process could claim the pid during the shutdown sleep
      if(`#{pid_exists_syscall}`)

        MyLogger.instance.warn(BE_LOG_HANDLE, "Pianobar process (#{@pianobar_pid}) still alive. Terminating forcibly.")

        begin
          Process.kill('TERM', @pianobar_pid)
        rescue Exception => e
          MyLogger.instance.warn(BE_LOG_HANDLE, "Exception termininating pianobar pid: #{e}")
        end
      else
        MyLogger.instance.info(BE_LOG_HANDLE, "Pianobar process successfully quit.")
      end



      @pianobar_pid = nil

      @@is_playing = false
    else
      MyLogger.instance.warn(BE_LOG_HANDLE, "Attempted to kill pianobar subprocess, but the pid was invalid: #{@pianobar_pid}")
    end

  end

  def write_pianobar_config

    MyLogger.instance.info(BE_LOG_HANDLE, "Writing pianobar config to #{@pianobar_config_file} using template #{@pianobar_config_template}")

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

    MyLogger.instance.info(BE_LOG_HANDLE, "Pianobar config written")

  end

  def write_pianobar_eventcmd
    #load template, set value hash, render template, write to location

    MyLogger.instance.info(BE_LOG_HANDLE, "Writing pianobar event script to #{@eventcmd_executable} using template #{@pianobar_event_script_template}")

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

    raise "Could not create event script at #{@eventcmd_executable}" unless File.exist?(@eventcmd_executable)

    File.chmod(0755, @eventcmd_executable) unless File.executable?(@eventcmd_executable)

    #already checked for file existence a few lines up
    raise "Could make event script executable at #{@eventcmd_executable}" unless File.executable?(@eventcmd_executable)

    MyLogger.instance.info(BE_LOG_HANDLE, "Pianobar event script written")
  end

  ####################
  #pianobar api api

  def pianobar_command(input)

    #single character for most
    #s123 for station change
    input = input[0..5]

    if(input =~ /[a-zA-Z\+\-\^\(\)]/)
      MyLogger.instance.info(BE_LOG_HANDLE, "Received pianobar command #{input}")

      #command_queue is a named pipe
      #TODO: check that a process is reading from the pipe
      #TODO: time out the echo, and restart the process
      #TODO: synchronize interaction
      retval = system("echo \"#{input}\" > #{@command_queue} &")

      if(!retval)
        MyLogger.instance.warn(BE_LOG_HANDLE, "Writing command #{input} to pipe has failed")
      else
        MyLogger.instance.debug(BE_LOG_HANDLE, "Writing command #{input} to pipe has succeeded")
      end
    else
      MyLogger.instance.warn(BE_LOG_HANDLE, "Ignoring invalid pianobar command")
    end

    #MyLogger.instance.info(BE_LOG_HANDLE,  "STDOUT read: #{$stdout.string}")

    return retval
  end

  #synchronous command
  def pianobar_command_sync(input)
    mod_time = File.mtime(@nowplaying_file)

    pianobar_command(input)

    #sleep? pianobar may take time to get the next song
    while(File.mtime(@nowplaying_file) == mod_time)
      MyLogger.instance.debug(BE_LOG_HANDLE, "sleeping, waiting for nowplaying update" )
      sleep(NOWPLAYING_SLEEP)
    end
  end

  def get_stations

    retval = "{}"

    if(File.exist?(@stationlist_file))

      #TODO: check last write date

      #check for lockfile first
      while(File.exist?( @stationlist_lock_file) )
        MyLogger.instance.warn(BE_LOG_HANDLE, "stations file being written to. waiting for lock file to be removed." )
        sleep(LOCKFILE_SLEEP)
      end

      begin
        #occasionally the nowplaying file contains incomplete json
        #TODO: sanitize file read before json parse
        stations_json = JSON.parse(File.read(@stationlist_file))
        retval = stations_json.to_json
      rescue JSON::ParserError => e
        MyLogger.instance.warn(BE_LOG_HANDLE, "Error parsing stations file #{@stationlist_file}: #{e}" )
      end
    else
      MyLogger.instance.warn(BE_LOG_HANDLE, "stations file does not exist #{@stationlist_file}" )
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
    content_type :json
    pianobar_command(PIANOBAR_KEYS["upcoming_song_key"])

    return "{'key' => 'value'}".to_json
  end

  def song_info
    retval = "{}"

    if(!@@player_stopped)
      max_attempts = 5
      attempts = 0

      while(attempts < max_attempts and retval == "{}" )

        if(File.exist?(@nowplaying_file) )
          #TODO: check last write date

          #check for lockfile first
          while(File.exist?( @nowplaying_lock_file) )
            MyLogger.instance.warn(BE_LOG_HANDLE, "nowplaying file being written to. waiting for lock file to be removed." )
            sleep(LOCKFILE_SLEEP)
          end

          begin
            #occasionally the nowplaying file contains incomplete or bad json
            #TODO: sanitize file read before json parse. enforce a keyset
            song_info_json = JSON.parse(File.read(@nowplaying_file))
            song_info_json["song"]["is_playing"] = @@is_playing
            song_info_json["song"]["player_stopped"] = @@player_stopped

            retval = song_info_json.to_json

            MyLogger.instance.debug(BE_LOG_HANDLE, "Current song is: #{retval}" )
          rescue JSON::ParserError => e
            MyLogger.instance.warn(BE_LOG_HANDLE, "Error parsing nowplaying file #{@nowplaying_file}: #{e}" )
          end
        else
          MyLogger.instance.warn(BE_LOG_HANDLE, "nowplaying file does not exist #{@nowplaying_file}" )
          attempts += 1
        end
      end
    else
      MyLogger.instance.warn(BE_LOG_HANDLE, "Song info request made on stopped player" )
      retval = "{\"song\":{\"player_stopped\":#{@@player_stopped}}}"
    end

    return retval
  end

  def change_station(station)
    pianobar_command_sync("s#{station}")

    pause unless @@is_playing
  end

  def quit

    #assume stop is called
    #TODO: call stop if not_stopped flag or something

    fork do
      MyLogger.instance.info(BE_LOG_HANDLE,"Pianobar Player exit thread started")
      sleep 20

      MyLogger.instance.debug(BE_LOG_HANDLE,"Pianobar Player exit thread terminating process")

      #kill ourselves :/
      Process.kill('TERM', @application_pid )

    end

    #exiter.start

    MyLogger.instance.debug(BE_LOG_HANDLE,"Pianobar Player quit returning")
  end

###############################################################
#web endpoints
###############################################################

  get "/#{@@webapp}" do
    content_type 'text/html'
    #ui bound with web requests to manipulate fifo on fs

    #TODO: better return vehicle for this
    return @player_page_html
  end

  get "/" do
    redirect "/#{@@webapp}"
  end

  get "/#{@@webapp}/" do
    redirect "/#{@@webapp}"
  end

  get "/#{@@webapp}/play" do
      content_type :json

      play

      return "{}"
  end

  get "/#{@@webapp}/is_playing" do
      @@is_playing.to_s
  end

  get "/#{@@webapp}/pause" do
      content_type :json

      pause

      return "{}"
  end

  get "/#{@@webapp}/next" do
      content_type :json

      next_song
      status 200

      return "{}"
  end

  get "/#{@@webapp}/like" do
      content_type :json

      pianobar_command(PIANOBAR_KEYS["love_song_key"])

      #update the nowplaying file with the new rating, since pianobar wont

      return "{}"
  end

  get "/#{@@webapp}/ban" do
    content_type :json

    ban

    return "{}"
  end

  get "/#{@@webapp}/stop" do
    content_type :json

    stop

    return "{}"
  end

  get "/#{@@webapp}/start" do
    content_type 'text/html'

    #calling start in this manner assumes no changes to the PianobarPlayer config.
    #for those the app needs to be restarted
    start

    #redirect to the player
    return @player_page_html
  end

  get "/#{@@webapp}/quit" do
    content_type :json

    MyLogger.instance.info(API_LOG_HANDLE,"Pianobar Player exiting")

    #in case we're paying attention to the console output


    stop



    #TODO: maybe fork a delayed exit and return a legit response

    #have to exit this way. sinatra rescues calls to SystemExit.

    quit

    #TODO: return html quit message

    #return "<html><body><b>Thanks for coming, please tip your server</b><br><a href=\"/player\">Return to player</a></body></html>"
    status 200

    return "{}"
  end

  get "/#{@@webapp}/song_info" do
    content_type :json

    song_info
  end

  get "/#{@@webapp}/getstations" do
    content_type :json

    get_stations
  end

  get "/#{@@webapp}/playstation" do
    content_type :json
    #station should be the index of the station list- a number something like 0-100

    #support a 10000-length station list as a max
    new_station = params[:station][0..5]

#    if(params[:station].size > 5 )
#      new_station = params[:station][0..5]
#    else
#      new_station = params[:station]
#    end

    #TODO: enforce the length in the regex too
    if(new_station =~ /\d+/)

      MyLogger.instance.info(API_LOG_HANDLE,"Changing pianobar station to #{new_station}")

      change_station(new_station)
    else
      MyLogger.instance.warn(API_LOG_HANDLE,"Ignoring invalid station change")

    end

    return "{}"
  end

  get "/#{@@webapp}/volup" do
    content_type :json

    pianobar_command(PIANOBAR_KEYS["vol_up_key"])
    status 200

    return "{}"
  end

  get "/#{@@webapp}/voldown" do

    content_type :json

    pianobar_command(PIANOBAR_KEYS["vol_down_key"])
    status 200

    return "{}"
  end

  get "/#{@@webapp}/volreset" do
    content_type :json

    pianobar_command(PIANOBAR_KEYS["vol_reset_key"])
    status 200

    return "{}"
  end
end
