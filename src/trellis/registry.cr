# src/trellis/registry.cr
require "sync/shared"
require "sync/mutex"

class Trellis::RegistryService
  @plugins = Sync::Shared(Hash(String, Injectable)).new(Hash(String, Injectable).new)
  @counter = 0
  @mutex   = Sync::Mutex.new

  def initialize(@ctx : Context)
  end

  def counter : Int32
    @mutex.synchronize { @counter += 1 }
  end

  def plugin(name : String, plugin_instance : Injectable) : Injectable
    @plugins.lock do |p|
      p[name] = plugin_instance
    end
    plugin_instance
  end

  def delete(name : String) : Nil
    @plugins.lock do |p|
      p.delete(name)
    end
  end

  def get(name : String) : Injectable?
    @plugins.shared { |p| p[name]? }
  end

  def has?(name : String) : Bool
    @plugins.shared { |p| p.has_key?(name) }
  end

  def names : Array(String)
    @plugins.shared { |p| p.keys }
  end

  def count : Int32
    @plugins.shared { |p| p.size }
  end

  def each(&block : Proc(String, Injectable, Nil)) : Nil
    @plugins.shared do |p|
      p.each { |name, plugin| block.call(name, plugin) }
    end
  end

  def clear : Nil
    @plugins.lock { |p| p.clear }
  end
end
