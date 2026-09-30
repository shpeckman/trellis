# spec/improvements_spec.cr
require "./spec_helper"

class ImprovementService < Trellis::Service
  def initialize(ctx : Trellis::Context, name : String = "improvement")
    super(ctx, name)
  end
end

describe "Trellis improvements" do
  it "raises specific service errors" do
    ctx = Trellis::Context.new
    svc = ImprovementService.new(ctx)

    expect_raises(Trellis::DuplicateServiceError, "Service already registered") do
      ctx.reflect.provide("improvement", svc)
    end

    expect_raises(Trellis::ServiceNotProvidedError, "Cannot set property without provide") do
      ctx.reflect.set("missing", svc)
    end

    expect_raises(Trellis::ServiceNotInjectedError, "Service not injected: missing") do
      ctx.service("missing")
    end
  end

  it "exposes reflection and registry introspection" do
    ctx = Trellis::Context.new
    svc = ImprovementService.new(ctx)
    ctx.registry.plugin("plugin", svc)

    ctx.reflect.registered_names.should contain("improvement")
    ctx.reflect.active?("improvement").should be_true
    ctx.reflect.impl("improvement").should_not be_nil
    ctx.service_active?("improvement").should be_true
    ctx.service("improvement").should eq(svc)
    ctx.registry.names.should contain("plugin")
    ctx.registry.count.should eq(1)
  end

  it "supports once listeners and listener counts" do
    ctx   = Trellis::Context.new
    value = 0

    once_event = ctx.events.channel("once_event", Nil)
    once_event.once do |_|
      value += 1
    end

    ctx.events.listener_count("once_event").should eq(1)
    once_event.emit(nil)
    once_event.emit(nil)
    value.should eq(1)
    ctx.events.listener_count("once_event").should eq(0)
  end

  it "supports typed event payloads" do
    ctx      = Trellis::Context.new
    received = ""

    handler = ->(payload : String) { received = payload; nil }
    typed = ctx.events.channel("typed_event", String)
    typed.on(&handler)
    typed.emit("payload")

    received.should eq("payload")
  end

  it "cancels cancellable hooks when parallel execution times out" do
    ctx       = Trellis::Context.new
    cancelled = Channel(Bool).new(1)

    slow = ctx.events.channel("slow_parallel", Nil)
    slow.on_cancellable do |_payload, token|
      token.on_cancel do
        cancelled.send(true)
        nil
      end
      sleep 5.seconds
      nil
    end

    expect_raises(Trellis::AggregateHookError, /TimeoutError/) do
      slow.parallel(nil, 10.milliseconds)
    end

    select
    when cancelled.receive
    when timeout(1.second)
      fail "cancellable hook was not cancelled"
    end
  end

  it "rejects new async event work after shutdown" do
    ctx = Trellis::Context.new
    ctx.events.shutdown

    expect_raises(Trellis::DisposedError, "EventsService is shut down") do
      ctx.events.channel("after_shutdown", Nil).background(nil)
    end
  end

  it "marks nodes failed when an active effect raises" do
    ctx  = Trellis::Context.new
    node = Trellis::LifecycleNode.new(ctx)

    expect_raises(RuntimeError, "boom") do
      node.effect { raise RuntimeError.new("boom") }
    end

    node.failed?.should be_true
    node.last_error.should_not be_nil
  end

  it "tracks disposal reason and lifecycle introspection" do
    ctx  = Trellis::Context.new
    node = Trellis::LifecycleNode.new(ctx)
    node.active?.should be_true
    node.dependencies_met?.should be_true
    node.effect_count.should eq(0)

    node.dispose("test shutdown")
    node.disposed?.should be_true
    node.dispose_reason.should eq("test shutdown")

    expect_raises(Trellis::DisposedError) do
      node.effect { -> { nil } }
    end
  end

  it "reads logger level from intercepted configuration" do
    ctx   = Trellis::Context.new
    child = ctx.intercept_logger(Trellis::LoggerLevel::ERROR)

    child.logger.level.should eq(Trellis::LoggerLevel::ERROR)
    ctx.logger.level.should eq(Trellis::LoggerLevel::DEBUG)
  end

  it "reads event timeout from intercepted configuration" do
    ctx   = Trellis::Context.new
    child = ctx.intercept_events(250.milliseconds)

    child.events.default_max_wait.should eq(250.milliseconds)
    ctx.events.default_max_wait.should eq(10.seconds)
  end
end
