# example/app.cr
require "../src/trellis"

class DatabaseService < Trellis::Service
  def initialize(ctx : Trellis::Context)
    super(ctx, "database")
  end

  def query(sql : String) : String
    "[{id: 1, name: \"Alice\"}, {id: 2, name: \"Bob\"}]"
  end
end

class WebServer
  include Trellis::Injectable

  def initialize(ctx : Trellis::Context)
    ctx.events.signal("server/request").on do |_|
      db     = ctx.database.as(DatabaseService)
      result = db.query("SELECT * FROM users")
      ctx.logger.info("Request processed: #{result}")
    end

    ctx.node.effect do
      ctx.logger.info("WebServer initialized and bound to port 8080")
      -> {
        ctx.logger.info("WebServer connection drained and shut down")
        nil
      }
    end
  end
end

class MetricPlugin
  include Trellis::Injectable

  def initialize(ctx : Trellis::Context)
    ctx.events.signal("server/request").on do |_|
      ctx.logger.debug("Metrics tracked for incoming request")
    end
  end
end

app = Trellis::Context.new

app.registry.plugin("database", DatabaseService.new(app))

api_context = app.isolate("api")
api_context.registry.plugin("web_server", WebServer.new(api_context))
api_context.registry.plugin("metrics", MetricPlugin.new(api_context))

app.events.signal("server/request").emit(nil)

app.node.dispose
