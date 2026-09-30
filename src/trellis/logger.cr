# src/trellis/logger.cr
require "log"

module Trellis
  enum LoggerLevel
    ERROR = 0
    WARN  = 1
    INFO  = 2
    DEBUG = 3
  end

  class LoggerIntercept < Intercept
    getter level : LoggerLevel

    def initialize(@level : LoggerLevel)
    end
  end

  class LoggerService
    def initialize(@ctx : Context)
    end

    def level : LoggerLevel
      @ctx.resolve_intercept("logger").as?(LoggerIntercept).try(&.level) || LoggerLevel::DEBUG
    end

    def error(msg : String) : Nil
      return unless enabled?(LoggerLevel::ERROR)
      Log.error { msg }
    end

    def warn(msg : String) : Nil
      return unless enabled?(LoggerLevel::WARN)
      Log.warn { msg }
    end

    def info(msg : String) : Nil
      return unless enabled?(LoggerLevel::INFO)
      Log.info { msg }
    end

    def debug(msg : String) : Nil
      return unless enabled?(LoggerLevel::DEBUG)
      Log.debug { msg }
    end

    private def enabled?(required : LoggerLevel) : Bool
      level.value >= required.value
    end
  end
end
