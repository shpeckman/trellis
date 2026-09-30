# spec/utils_spec.cr
require "./spec_helper"

describe Trellis::DisposableList do
  it "pushes and returns an untrack function" do
    list  = Trellis::DisposableList.new
    value = 0

    proc    = -> { value += 1; nil }
    untrack = list.push(proc)

    untrack.call.should be_true
    untrack.call.should be_false

    value.should eq(0)
  end

  it "clears all disposables and returns them in reverse order without calling them" do
    list   = Trellis::DisposableList.new
    values = Array(Int32).new

    proc1 = -> { values << 1; nil }
    proc2 = -> { values << 2; nil }

    list.push(proc1)
    list.push(proc2)

    items = list.clear
    items.should eq([proc2, proc1])

    values.should be_empty
  end

  it "deletes a specific disposable" do
    list  = Trellis::DisposableList.new
    value = 0

    proc = -> { value += 1; nil }
    list.push(proc)
    list.delete(proc).should be_true
    list.clear.should be_empty
  end
end
