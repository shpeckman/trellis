# spec/registry_spec.cr
require "./spec_helper"

class MockPlugin
  include Trellis::Injectable
end

describe Trellis::RegistryService do
  it "manages plugin registration and lifecycle" do
    ctx    = Trellis::Context.new
    plugin = MockPlugin.new

    ctx.registry.plugin("mock_plugin", plugin)
    ctx.registry.has?("mock_plugin").should be_true
    ctx.registry.get("mock_plugin").should eq(plugin)

    ctx.registry.delete("mock_plugin")
    ctx.registry.has?("mock_plugin").should be_false
  end

  it "increments the counter atomically" do
    ctx = Trellis::Context.new

    ctx.registry.counter.should eq(1)
    ctx.registry.counter.should eq(2)
    ctx.registry.counter.should eq(3)
  end
end
