# spec/events_spec.cr
require "./spec_helper"

record EventPayload, key : String

describe Trellis::EventsService do
  it "registers and emits events" do
    ctx   = Trellis::Context.new
    value = 0

    numbers = ctx.events.channel("increment", Int32)
    numbers.on do |n|
      value += n
    end

    numbers.emit(5)
    value.should eq(5)
  end

  it "removes event listeners via disposable" do
    ctx   = Trellis::Context.new
    value = 0

    numbers = ctx.events.channel("increment", Int32)
    dispose = numbers.on do |n|
      value += n
    end

    dispose.call
    numbers.emit(5)
    value.should eq(0)
  end

  it "handles serial execution in order" do
    ctx   = Trellis::Context.new
    order = Array(Int32).new

    pipeline = ctx.events.channel("pipeline", Int32)
    pipeline.on do |n|
      order << n
    end
    pipeline.on do |n|
      order << n * 2
    end

    pipeline.serial(21)
    order.should eq([21, 42])
  end

  it "handles bail which delegates to serial" do
    ctx   = Trellis::Context.new
    value = 0

    pipeline = ctx.events.channel("pipeline", Int32)
    pipeline.on do |n|
      value = n
    end

    pipeline.bail(42)
    value.should eq(42)
  end

  it "handles parallel execution" do
    ctx   = Trellis::Context.new
    mutex = Sync::Mutex.new
    value = 0

    par = ctx.events.channel("par", Nil)
    par.on do |_|
      mutex.synchronize { value += 1 }
      nil
    end

    par.on do |_|
      mutex.synchronize { value += 2 }
      nil
    end

    par.parallel(nil)
    value.should eq(3)
  end

  it "handles background execution without blocking" do
    ctx     = Trellis::Context.new
    channel = Channel(Bool).new

    bg = ctx.events.channel("bg", Nil)
    bg.on do |_|
      channel.send(true)
    end

    bg.background(nil)
    channel.receive.should be_true
  end

  it "uses custom execution contexts for async events" do
    ctx      = Trellis::Context.new
    exec_ctx = Fiber::ExecutionContext::Concurrent.new("test_exec")
    ctx.execution_context = exec_ctx

    ran_in_context = false

    test = ctx.events.channel("test", Nil)
    test.on do |_|
      ran_in_context = Fiber.current.execution_context == exec_ctx
    end

    test.parallel(nil)
    ran_in_context.should be_true
  end

  it "passes typed struct payloads without casting" do
    ctx          = Trellis::Context.new
    received_val = ""

    payloads = ctx.events.channel("payload_event", EventPayload)
    payloads.on do |payload|
      received_val = payload.key
    end

    payloads.emit(EventPayload.new("decoded_value"))
    received_val.should eq("decoded_value")
  end

  it "raises when a channel is reused with a different payload type" do
    ctx = Trellis::Context.new
    ctx.events.channel("typed_channel", Int32)

    expect_raises(Trellis::EventTypeMismatchError) do
      ctx.events.channel("typed_channel", String)
    end
  end

  it "times out parallel execution if a hook hangs" do
    ctx = Trellis::Context.new

    hang = ctx.events.channel("hang_par", Nil)
    hang.on do |_|
      sleep 5.seconds
      nil
    end

    expect_raises(Trellis::AggregateHookError, /TimeoutError/) do
      hang.parallel(nil, 10.milliseconds)
    end
  end

  it "times out serial execution if a hook hangs" do
    ctx = Trellis::Context.new

    hang = ctx.events.channel("hang_ser", Nil)
    hang.on do |_|
      sleep 5.seconds
      nil
    end

    expect_raises(Trellis::DependencyTimeoutError, /TimeoutError/) do
      hang.serial(nil, 10.milliseconds)
    end
  end
end
