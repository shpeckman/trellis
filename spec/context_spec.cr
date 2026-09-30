# spec/context_spec.cr
require "./spec_helper"

class DynamicService < Trellis::Service
  def execute
    "executed"
  end
end

describe Trellis::Context do
  it "initializes root properties correctly" do
    ctx = Trellis::Context.new

    ctx.root.should eq(ctx)
    ctx.node.state.should eq(Trellis::NodeState::ACTIVE)
    ctx.isolate.empty?.should be_true
    ctx.execution_context.should eq(Fiber::ExecutionContext.default)
  end

  it "extends contexts" do
    ctx   = Trellis::Context.new
    child = ctx.extend_context

    child.root.should eq(ctx.root)
    child.should_not eq(ctx)
  end

  it "inherits execution_context on extend" do
    ctx      = Trellis::Context.new
    exec_ctx = Fiber::ExecutionContext::Concurrent.new("test_exec")
    ctx.execution_context = exec_ctx

    child = ctx.extend_context
    child.execution_context.should eq(exec_ctx)
  end

  it "isolates contexts" do
    ctx   = Trellis::Context.new
    child = ctx.isolate("database")

    child.isolate.has_key?("database").should be_true
    ctx.isolate.has_key?("database").should be_false
  end

  it "intercepts contexts" do
    ctx   = Trellis::Context.new
    child = ctx.intercept_logger(Trellis::LoggerLevel::DEBUG)

    child.intercept["logger"].as(Trellis::LoggerIntercept).level.should eq(Trellis::LoggerLevel::DEBUG)
    ctx.intercept.has_key?("logger").should be_false
  end

  it "intercepts contexts with event timeout configuration" do
    ctx   = Trellis::Context.new
    child = ctx.intercept_events(250.milliseconds)

    child.intercept["events"].as(Trellis::EventTimeoutIntercept).max_wait.should eq(250.milliseconds)
    ctx.intercept.has_key?("events").should be_false
  end

  it "resolves intercepts through the parent chain" do
    ctx        = Trellis::Context.new
    child      = ctx.intercept_logger(Trellis::LoggerLevel::WARN)
    grandchild = child.extend_context

    grandchild.resolve_intercept("logger").as(Trellis::LoggerIntercept).level.should eq(Trellis::LoggerLevel::WARN)
  end

  it "resolves dynamic properties via method_missing macro" do
    ctx = Trellis::Context.new
    svc = DynamicService.new(ctx, "dynamic_svc")

    resolved = ctx.dynamic_svc.as(DynamicService)
    resolved.execute.should eq("executed")
  end

  it "raises on missing dynamic properties" do
    ctx = Trellis::Context.new

    expect_raises(Exception, "Service not injected: nonexistent_svc") do
      ctx.nonexistent_svc
    end
  end
end
