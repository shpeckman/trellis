# src/trellis/context.cr
require "random/secure"

class Trellis::Context
  property parent            : Context?
  property isolate           : Hash(String, String)
  property intercept         : Hash(String, Intercept)
  property execution_context : Fiber::ExecutionContext
  property! root             : Context
  property! node             : LifecycleNode
  property! registry         : RegistryService
  property! events           : EventsService
  property! reflect          : ReflectService
  property! logger           : LoggerService

  def initialize
    @parent            = nil
    @isolate           = Hash(String, String).new
    @intercept         = Hash(String, Intercept).new
    @execution_context = Fiber::ExecutionContext.default
    @root              = self

    @events   = EventsService.new(self)
    @reflect  = ReflectService.new(self)
    @registry = RegistryService.new(self)
    @logger   = LoggerService.new(self)

    @node = LifecycleNode.new(self, true)
  end

  protected def initialize(parent : Context, node : LifecycleNode)
    @parent            = parent
    @isolate           = Hash(String, String).new
    @intercept         = Hash(String, Intercept).new
    @execution_context = parent.execution_context
    @root              = parent.root
    @reflect           = ReflectService.new(self, parent.reflect.store)
    @events            = EventsService.new(self, parent.events.state)
    @registry          = parent.registry
    @logger            = LoggerService.new(self)
    @node              = node
  end

  def resolve_isolate(name : String) : String?
    current : Context? = self
    while current
      return current.isolate[name] if current.isolate.has_key?(name)
      current = current.parent
    end
    nil
  end

  def resolve_intercept(name : String) : Intercept?
    current : Context? = self
    while current
      return current.intercept[name] if current.intercept.has_key?(name)
      current = current.parent
    end
    nil
  end

  def extend_context(meta : Hash(String, String)? = nil) : Context
    child = Context.new(self, self.node)
    child.isolate.merge!(meta) if meta
    child
  end

  def isolate(name : String) : Context
    child = extend_context
    child.isolate[name] = "#{name}_#{Random::Secure.hex(4)}"
    child
  end

  def intercept(name : String, config : Intercept) : Context
    child = extend_context
    child.intercept[name] = config
    child
  end

  def intercept_logger(level : LoggerLevel) : Context
    intercept("logger", LoggerIntercept.new(level))
  end

  def intercept_events(max_wait : Time::Span) : Context
    intercept("events", EventTimeoutIntercept.new(max_wait))
  end

  def service(name : String) : Injectable
    result = reflect.get(name, strict: true)
    raise ServiceNotInjectedError.new("Service not injected: " + name) if result.nil?
    result
  end

  def service?(name : String) : Injectable?
    reflect.get(name, strict: true)
  end

  def service_active?(name : String) : Bool
    reflect.active?(name)
  end

  def dispose(reason : String = "disposed") : Nil
    node.dispose(reason)
  end

  macro method_missing(call)
    if reflect.get({{call.name.stringify}})
      reflect.get({{call.name.stringify}})
    else
      raise ::Trellis::ServiceNotInjectedError.new("Service not injected: " + {{call.name.stringify}})
    end
  end
end
