require 'logger'

class MyLogger

  def initialize
    logdir = "#{ File.dirname(__FILE__) }/../log"
    Dir.mkdir(logdir) unless File.exists?(logdir)

    raise "Could not create log directory #{logdir}" unless Dir.exists?(logdir)

    logfile = "#{ logdir }/pianobarplayer.log"

    #turn on sync. sometimes messages don't make it to the logs if there's a threading problem
    io = File.open( logfile, "a")
    io.sync = true

    @log = Logger.new( io )

    raise "Could not create log file #{logfile}" unless File.exists?(logfile)

  end

  @@instance = MyLogger.new

  def self.instance
    return @@instance
  end

  def setLevel(level)
    if(level == "debug")
      @log.level = Logger::DEBUG
    elsif(level == "info")
      @log.level = Logger::INFO
    elsif(level == "error")
      @log.level = Logger::ERROR
    elsif(level == "warn")
      @log.level = Logger::WARN
    end
  end

  def debug(handle, msg)
    @log.debug("#{handle} #{msg}")
  end

  def info(handle, msg)
    @log.info("#{handle} #{msg}")
  end

  def error(handle, msg)
    @log.error("#{handle} #{msg}")
  end

  def warn(handle, msg)
    @log.warn("#{handle} #{msg}")
  end

  private_class_method :new
end
