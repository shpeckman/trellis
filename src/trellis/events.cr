# src/trellis/events.cr
require "sync/shared"
require "sync/mutex"

class Trellis::EventTimeoutIntercept < Trellis::Intercept
  getter max_wait : Time::Span

  def initialize(@max_wait : Time::Span)
  end
end

abstract class Trellis::EventChannelBase
  getter name : String

  def initialize(@name : String)
  end

  abstract def listener_count : Int32
end

class Trellis::ChannelState(T) < Trellis::EventChannelBase
  @hooks = Sync::Shared(Array(Proc(T, Nil) | Proc(T, CancellationToken, Nil))).new(Array(Proc(T, Nil) | Proc(T, CancellationToken, Nil)).new)

  def add(entry : Proc(T, Nil) | Proc(T, CancellationToken, Nil)) : Nil
    @hooks.lock { |h| h << entry }
  end

  def remove(entry : Proc(T, Nil) | Proc(T, CancellationToken, Nil)) : Nil
    @hooks.lock { |h| h.delete(entry) }
  end

  def snapshot : Array(Proc(T, Nil) | Proc(T, CancellationToken, Nil))
    @hooks.shared { |h| h.dup }
  end

  def listener_count : Int32
    @hooks.shared { |h| h.size }
  end
end

class Trellis::EventChannel(T)
  getter name : String

  def initialize(@events : EventsService, @state : ChannelState(T))
    @name = @state.name
  end

  def on(&block : Proc(T, Nil)) : Disposable
    entry = block
    @state.add(entry)
    -> {
      @state.remove(entry)
      nil
    }
  end

  def on_cancellable(&block : Proc(T, CancellationToken, Nil)) : Disposable
    entry = block
    @state.add(entry)
    -> {
      @state.remove(entry)
      nil
    }
  end

  def once(&block : Proc(T, Nil)) : Disposable
    disposable = -> { nil }
    wrapper = ->(payload : T) : Nil {
      block.call(payload)
      disposable.call
    }
    disposable = on(&wrapper)
    disposable
  end

  def emit(payload : T) : Nil
    hooks = @state.snapshot
    return if hooks.empty?
    token = CancellationToken.new
    hooks.each { |entry| call_entry(entry, payload, token) }
  end

  def background(payload : T) : Nil
    @events.ensure_running!
    hooks = @state.snapshot
    return if hooks.empty?

    token = CancellationToken.new
    @events.register_token(token)
    hooks.each do |entry|
      @events.spawn_tracked(name) do
        begin
          call_entry(entry, payload, token)
        rescue ex
          @events.log_hook_error(name, ex)
        end
      end
    end
    @events.unregister_token(token)
  end

  def parallel(payload : T, max_wait : Time::Span? = nil) : Nil
    @events.ensure_running!
    hooks = @state.snapshot
    return if hooks.empty?

    wait    = max_wait || @events.default_max_wait
    channel = Channel(Exception?).new(hooks.size)
    token   = CancellationToken.new
    @events.register_token(token)

    hooks.each do |entry|
      @events.spawn_tracked(name) do
        begin
          call_entry(entry, payload, token)
          channel.send(nil)
        rescue ex
          channel.send(ex)
        end
      end
    end

    errors = Array(Exception).new
    hooks.size.times do
      select
      when result = channel.receive
        errors << result if result.is_a?(Exception)
      when timeout(wait)
        token.cancel
        errors << DependencyTimeoutError.new("TimeoutError: Hook execution for '#{name}' exceeded timeout")
        break
      end
    end

    @events.unregister_token(token)
    raise AggregateHookError.new(errors) unless errors.empty?
  end

  def serial(payload : T, max_wait : Time::Span? = nil) : Nil
    @events.ensure_running!
    hooks = @state.snapshot
    return if hooks.empty?

    wait    = max_wait || @events.default_max_wait
    channel = Channel(Exception?).new(1)
    token   = CancellationToken.new
    @events.register_token(token)

    @events.spawn_tracked(name) do
      begin
        hooks.each do |entry|
          break if token.cancelled?
          call_entry(entry, payload, token)
        end
        channel.send(nil)
      rescue ex
        channel.send(ex)
      end
    end

    select
    when result = channel.receive
      @events.unregister_token(token)
      raise result if result
    when timeout(wait)
      token.cancel
      @events.unregister_token(token)
      raise DependencyTimeoutError.new("TimeoutError: Hook execution for '#{name}' exceeded timeout")
    end
  end

  def bail(payload : T, max_wait : Time::Span? = nil) : Nil
    serial(payload, max_wait)
  end

  def listener_count : Int32
    @state.listener_count
  end

  private def call_entry(entry : Proc(T, Nil) | Proc(T, CancellationToken, Nil), payload : T, token : CancellationToken) : Nil
    case entry
    when Proc(T, CancellationToken, Nil)
      entry.call(payload, token)
    else
      entry.call(payload)
    end
  end
end

class Trellis::EventsService
  class State
    @channels = Sync::Shared(Hash(String, EventChannelBase)).new(Hash(String, EventChannelBase).new)

    @pending_mutex = Sync::Mutex.new
    @pending       = Hash(String, Int32).new
    @tokens        = Array(CancellationToken).new
    @shutdown      = false

    def get_or_create(name : String, type : T.class) : ChannelState(T) forall T
      if existing = @channels.shared { |h| h[name]? }
        return cast(name, existing, T)
      end

      @channels.lock do |h|
        if existing = h[name]?
          cast(name, existing, T)
        else
          created = ChannelState(T).new(name)
          h[name] = created
          created
        end
      end
    end

    def listener_count(name : String) : Int32
      @channels.shared { |h| h[name]?.try(&.listener_count) || 0 }
    end

    def event_names : Array(String)
      @channels.shared { |h| h.keys }
    end

    def shutdown? : Bool
      @pending_mutex.synchronize { @shutdown }
    end

    def shutdown(timeout : Time::Span = 10.seconds) : Nil
      tokens = @pending_mutex.synchronize do
        @shutdown = true
        @tokens.dup
      end
      tokens.each &.cancel

      deadline = Time.local + timeout
      while pending_total > 0 && Time.local < deadline
        sleep 1.millisecond
      end

      if pending_total > 0
        raise DependencyTimeoutError.new("TimeoutError: EventsService shutdown exceeded timeout")
      end
    end

    def register_token(token : CancellationToken) : Nil
      @pending_mutex.synchronize { @tokens << token }
    end

    def unregister_token(token : CancellationToken) : Nil
      @pending_mutex.synchronize { @tokens.delete(token) }
    end

    def track(name : String) : Nil
      @pending_mutex.synchronize do
        @pending[name] = (@pending[name]? || 0) + 1
      end
    end

    def untrack(name : String) : Nil
      @pending_mutex.synchronize do
        return unless count = @pending[name]?
        if count <= 1
          @pending.delete(name)
        else
          @pending[name] = count - 1
        end
      end
    end

    private def pending_total : Int32
      @pending_mutex.synchronize { @pending.values.sum }
    end

    private def cast(name : String, base : EventChannelBase, type : T.class) : ChannelState(T) forall T
      typed = base.as?(ChannelState(T))
      unless typed
        raise EventTypeMismatchError.new("Event channel '#{name}' already exists with a different payload type")
      end
      typed
    end
  end

  protected property state : State

  def initialize(@ctx : Context, @state : State = State.new)
  end

  def channel(name : String, type : T.class) : EventChannel(T) forall T
    EventChannel(T).new(self, @state.get_or_create(name, T))
  end

  def signal(name : String) : EventChannel(Nil)
    channel(name, Nil)
  end

  def listener_count(name : String) : Int32
    @state.listener_count(name)
  end

  def event_names : Array(String)
    @state.event_names
  end

  def shutdown? : Bool
    @state.shutdown?
  end

  def shutdown(timeout : Time::Span = 10.seconds) : Nil
    @state.shutdown(timeout)
  end

  def default_max_wait : Time::Span
    if intercept = @ctx.resolve_intercept("events").as?(EventTimeoutIntercept)
      intercept.max_wait
    else
      10.seconds
    end
  end

  def ensure_running! : Nil
    if @state.shutdown?
      raise DisposedError.new("EventsService is shut down")
    end
  end

  def register_token(token : CancellationToken) : Nil
    @state.register_token(token)
  end

  def unregister_token(token : CancellationToken) : Nil
    @state.unregister_token(token)
  end

  def log_hook_error(name : String, ex : Exception) : Nil
    @ctx.logger.error("Background execution error in hook '#{name}': #{ex.message}")
  end

  def spawn_tracked(name : String, &block : -> Nil) : Nil
    @state.track(name)
    @ctx.execution_context.spawn do
      begin
        block.call
      ensure
        @state.untrack(name)
      end
    end
  end
end
