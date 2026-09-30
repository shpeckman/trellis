# src/trellis/errors.cr
module Trellis
  class Error < Exception
  end

  class ServiceNotFoundError < Error
  end

  class ServiceNotInjectedError < Error
  end

  class DuplicateServiceError < Error
  end

  class ServiceNotProvidedError < Error
  end

  class DependencyTimeoutError < Error
  end

  class HookExecutionError < Error
  end

  class AggregateHookError < Error
    getter errors : Array(Exception)

    def initialize(@errors : Array(Exception))
      super("AggregateError: #{errors.map(&.message).join(", ")}")
    end
  end

  class EventTypeMismatchError < Error
  end

  class LifecycleError < Error
  end

  class DisposedError < LifecycleError
  end
end
