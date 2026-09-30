module Trellis
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end