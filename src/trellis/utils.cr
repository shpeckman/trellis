# src/trellis/utils.cr
require "sync/mutex"

module Trellis
  module Injectable
    macro inject(*services)
      def inject : Array(String)
        [ {{ services.map(&.id.stringify).splat }} ]
      end
    end

    def inject : Array(String)
      Array(String).new
    end
  end

  alias Disposable = Proc(Nil)

  class CancellationToken
    @mutex     = Sync::Mutex.new
    @cancelled = false
    @callbacks = Array(Disposable).new

    def cancelled? : Bool
      @mutex.synchronize { @cancelled }
    end

    def cancel : Nil
      callbacks = @mutex.synchronize do
        if @cancelled
          Array(Disposable).new
        else
          @cancelled = true
          values     = @callbacks.dup
          @callbacks.clear
          values
        end
      end
      callbacks.each &.call
    end

    def on_cancel(&block : Disposable) : Disposable
      run_now = false
      @mutex.synchronize do
        if @cancelled
          run_now = true
        else
          @callbacks << block
        end
      end
      block.call if run_now
      -> {
        @mutex.synchronize { @callbacks.delete(block) }
        nil
      }
    end
  end

  class DisposableList
    @disposables = Array(Disposable).new
    @mutex       = Sync::Mutex.new

    def push(proc : Disposable) : Proc(Bool)
      @mutex.synchronize { @disposables << proc }
      -> { delete(proc) }
    end

    def delete(proc : Disposable) : Bool
      @mutex.synchronize { !!@disposables.delete(proc) }
    end

    def clear : Array(Disposable)
      @mutex.synchronize do
        values = @disposables.reverse
        @disposables.clear
        values
      end
    end

    def size : Int32
      @mutex.synchronize { @disposables.size }
    end

    def empty? : Bool
      size == 0
    end
  end
end
