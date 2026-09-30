# spec/logger_spec.cr
require "./spec_helper"

describe Trellis::LoggerService do
  it "provides basic logging methods without error" do
    ctx = Trellis::Context.new

    ctx.logger.info("info test")
    ctx.logger.error("error test")
    ctx.logger.warn("warn test")
    ctx.logger.debug("debug test")
  end
end
