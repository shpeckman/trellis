# spec/service_spec.cr
require "./spec_helper"

class TestService < Trellis::Service
  property value : Int32 = 0
end

describe Trellis::Service do
  it "automatically registers itself via reflect on initialization" do
    ctx     = Trellis::Context.new
    service = TestService.new(ctx, "test_svc")

    resolved = ctx.reflect.get("test_svc")
    resolved.should_not be_nil
    resolved.should be_a(TestService)
  end
end
