# src/trellis.cr
require "./trellis/errors"
require "./trellis/intercept"
require "./trellis/macros"
require "./trellis/utils"
require "./trellis/logger"
require "./trellis/events"
require "./trellis/lifecycle_node"
require "./trellis/reflect"
require "./trellis/registry"
require "./trellis/context"
require "./trellis/service"

module Trellis
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
