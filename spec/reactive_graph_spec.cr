# spec/reactive_graph_spec.cr
require "./spec_helper"

class BaseDatabase < Trellis::Service
  def initialize(ctx : Trellis::Context)
    super(ctx, "database")
  end
end

class NeedsDatabase < Trellis::Service
  inject "database"

  property initialized_effect = false

  def initialize(ctx : Trellis::Context)
    super(ctx, "needs_database")

    # Use self.ctx (the isolated node created by super), not the parent ctx parameter.
    self.ctx.node.effect do
      @initialized_effect = true
      -> {
        @initialized_effect = false
        nil
      }
    end
  end
end

describe "Reactive Dependency Graph" do
  it "defers execution of a plugin until its inject dependencies are met" do
    app = Trellis::Context.new

    svc = NeedsDatabase.new(app)

    # NeedsDatabase injected "database" but it doesn't exist yet, so node sits in PENDING
    sleep 20.milliseconds
    svc.ctx.node.state.should eq(Trellis::NodeState::PENDING)
    svc.initialized_effect.should be_false

    # Fulfilling the dependency should awaken the node reactively
    db = BaseDatabase.new(app)
    sleep 20.milliseconds

    svc.ctx.node.state.should eq(Trellis::NodeState::ACTIVE)
    svc.initialized_effect.should be_true

    # Removing/Disposing the dependency should safely suspend the node again
    db.ctx.node.dispose
    sleep 20.milliseconds

    svc.ctx.node.state.should eq(Trellis::NodeState::SUSPENDED)
    svc.initialized_effect.should be_false
  end
end
