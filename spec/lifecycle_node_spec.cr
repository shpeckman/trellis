# spec/lifecycle_node_spec.cr
require "./spec_helper"

describe Trellis::LifecycleNode do
  it "initializes and activates automatically if no dependencies" do
    ctx  = Trellis::Context.new
    node = Trellis::LifecycleNode.new(ctx)

    node.state.should eq(Trellis::NodeState::ACTIVE)
  end

  it "handles effects and state changes on disposal" do
    ctx   = Trellis::Context.new
    node  = Trellis::LifecycleNode.new(ctx)
    value = 0

    node.effect { -> { value += 1; nil } }
    node.dispose

    node.state.should eq(Trellis::NodeState::DISPOSED)
    value.should eq(1)
  end

  it "returns a wrapper from effect that untracks and executes" do
    ctx   = Trellis::Context.new
    node  = Trellis::LifecycleNode.new(ctx)
    value = 0

    wrapper = node.effect { -> { value += 1; nil } }
    wrapper.call

    value.should eq(1)

    node.dispose
    value.should eq(1)
  end
end
