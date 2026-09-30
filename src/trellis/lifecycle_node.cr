# src/trellis/lifecycle_node.cr
module Trellis
  enum NodeState
    PENDING
    LOADING
    ACTIVE
    FAILED
    DISPOSED
    UNLOADING
    SUSPENDED
  end

  class EffectRecord
    property name     : String?
    property block    : Proc(Disposable)
    property teardown : Disposable?
    property untrack  : Proc(Bool)?

    def initialize(@block : Proc(Disposable), @name : String? = nil)
    end
  end

  class LifecycleNode
    property uid             : Int32?
    property ctx             : Context
    property state           : NodeState
    property inject          : Array(String)
    property dispose_tasks   : DisposableList
    property last_error      : Exception?
    property dispose_reason  : String?
    property last_transition : Time

    @effects             = Array(EffectRecord).new
    @disposables         = DisposableList.new
    @dependency_untracks = Array(Disposable).new

    def initialize(parent : Context, is_root : Bool = false, inject : Array(String) = Array(String).new)
      @uid                 = 1
      @effects             = Array(EffectRecord).new
      @disposables         = DisposableList.new
      @dispose_tasks       = DisposableList.new
      @inject              = inject.dup
      @dependency_untracks = Array(Disposable).new
      @last_error          = nil
      @dispose_reason      = nil
      @last_transition     = Time.utc

      if is_root
        @ctx   = parent
        @state = NodeState::ACTIVE
      else
        @ctx   = parent.extend_context
        @state = NodeState::PENDING
        @ctx.node = self
        refresh_subscriptions
        update_state
      end
    end

    def add_inject(deps : Array(String)) : Nil
      @inject.concat(deps).uniq!
      refresh_subscriptions
      update_state
    end

    def retry : Nil
      return if @state == NodeState::DISPOSED || @state == NodeState::UNLOADING
      @last_error = nil
      transition_to(NodeState::PENDING)
      update_state
    end

    def effect(name : String? = nil, &block : -> Disposable) : Disposable
      if @state == NodeState::DISPOSED || @state == NodeState::UNLOADING
        raise DisposedError.new("Cannot add effect to #{@state.to_s.downcase} lifecycle node")
      end

      record = EffectRecord.new(block, name)
      @effects << record

      if @state == NodeState::ACTIVE
        begin
          activate_record(record)
        rescue ex
          fail_from_effect(ex)
          raise ex
        end
      end

      -> {
        @effects.delete(record)
        if (u_proc = record.untrack) && (t_proc = record.teardown)
          if u_proc.call
            begin
              t_proc.call
            rescue ex
              @last_error = ex
            end
          end
        end
        record.untrack = nil
        record.teardown = nil
        nil
      }
    end

    def update_state : Nil
      return if @state == NodeState::DISPOSED || @state == NodeState::UNLOADING

      all_met = dependencies_met?

      if all_met && (@state == NodeState::PENDING || @state == NodeState::SUSPENDED)
        transition_to(NodeState::LOADING)
        begin
          @effects.each { |record| activate_record(record) }
          transition_to(NodeState::ACTIVE)
        rescue ex
          teardown_errors = clear_effect_teardowns
          error           = teardown_errors.empty? ? ex : AggregateHookError.new([ex] + teardown_errors)
          transition_to(NodeState::FAILED, error)
        end
        emit_update
      elsif !all_met && (@state == NodeState::ACTIVE || @state == NodeState::LOADING || @state == NodeState::FAILED)
        transition_to(NodeState::UNLOADING)
        errors = clear_effect_teardowns
        if errors.empty?
          transition_to(NodeState::SUSPENDED)
        else
          transition_to(NodeState::FAILED, AggregateHookError.new(errors))
        end
        emit_update
      end
    end

    def dispose(reason : String = "disposed") : Nil
      return if @state == NodeState::DISPOSED
      transition_to(NodeState::UNLOADING)
      @dispose_reason = reason
      @dependency_untracks.each &.call
      @dependency_untracks.clear

      errors = clear_effect_teardowns
      @effects.clear
      @dispose_tasks.clear.each do |task|
        begin
          task.call
        rescue ex
          errors << ex
        end
      end

      @last_error = AggregateHookError.new(errors) unless errors.empty?
      transition_to(NodeState::DISPOSED)
      emit_update
    end

    def dispose_async(reason : String = "disposed") : Nil
      @ctx.execution_context.spawn do
        dispose(reason)
      end
    end

    def dependencies_met? : Bool
      @inject.each do |dep|
        return false if @ctx.reflect.get(dep, strict: true).nil?
      end
      true
    end

    def pending? : Bool
      @state == NodeState::PENDING
    end

    def loading? : Bool
      @state == NodeState::LOADING
    end

    def active? : Bool
      @state == NodeState::ACTIVE
    end

    def suspended? : Bool
      @state == NodeState::SUSPENDED
    end

    def failed? : Bool
      @state == NodeState::FAILED
    end

    def disposed? : Bool
      @state == NodeState::DISPOSED
    end

    def unloading? : Bool
      @state == NodeState::UNLOADING
    end

    def effect_count : Int32
      @effects.size
    end

    def disposable_count : Int32
      @disposables.size
    end

    private def refresh_subscriptions : Nil
      @dependency_untracks.each &.call
      @dependency_untracks.clear
      return if @ctx.root.same?(@ctx) && @state == NodeState::ACTIVE

      events = @ctx.root.events
      @inject.each do |dep|
        @dependency_untracks << events.signal("internal/update:#{dep}").on { |_| update_state }
      end
      @dependency_untracks << events.signal("internal/isolate").on { |_| update_state }
      @dependency_untracks << events.signal("internal/update").on { |_| update_state }
    end

    private def activate_record(record : EffectRecord) : Nil
      return if record.teardown
      eff_proc = record.block.call
      record.teardown = eff_proc
      record.untrack = @disposables.push(eff_proc)
    end

    private def clear_effect_teardowns : Array(Exception)
      errors = Array(Exception).new
      @disposables.clear.each do |teardown|
        begin
          teardown.call
        rescue ex
          errors << ex
        end
      end
      @effects.each do |record|
        record.teardown = nil
        record.untrack = nil
      end
      errors
    end

    private def fail_from_effect(ex : Exception) : Nil
      errors      = clear_effect_teardowns
      @last_error = errors.empty? ? ex : AggregateHookError.new([ex] + errors)
      transition_to(NodeState::FAILED, @last_error)
      emit_update
    end

    private def transition_to(state : NodeState, error : Exception? = nil) : Nil
      @state           = state
      @last_transition = Time.utc
      @last_error      = error if error
      @ctx.root.events.channel("lifecycle/#{state.to_s.downcase}", NodeState).background(state) rescue nil
    end

    private def emit_update : Nil
      @ctx.root.events.signal("internal/update").background(nil) rescue nil
    end
  end
end
