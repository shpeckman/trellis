# spec/macros_spec.cr
require "./spec_helper"

class LoggerPlugin < Trellis::Service
  def initialize(ctx : Trellis::Context)
    super(ctx, "logger_plugin")
  end

  def log(msg : String)
    "Logged: #{msg}"
  end
end

# Generates typed accessors on Trellis::Context
Trellis.define_service("logger_plugin", LoggerPlugin)

describe "Trellis Macros" do
  it "generates strictly typed getters via define_service" do
    app = Trellis::Context.new
    LoggerPlugin.new(app)

    # Resolves directly as LoggerPlugin without .as(LoggerPlugin)
    result = app.logger_plugin.log("test")
    result.should eq("Logged: test")

    app.logger_plugin?.should_not be_nil
  end

  it "raises clearly if a strictly typed macro service is missing" do
    app = Trellis::Context.new

    app.logger_plugin?.should be_nil

    expect_raises(Exception, "Service not injected or inactive: logger_plugin") do
      app.logger_plugin
    end
  end
end
