# example/reactive_app.cr
require "../src/trellis"

class DatabaseService < Trellis::Service
  def initialize(ctx : Trellis::Context)
    super(ctx, "database")
  end

  def query(sql : String) : String
    "[{id: 1, name: \"Alice\"}, {id: 2, name: \"Bob\"}]"
  end
end

Trellis.define_service("database", DatabaseService)

class UserRepository < Trellis::Service
  inject "database"

  def initialize(ctx : Trellis::Context)
    super(ctx, "user_repository")

    self.ctx.node.effect do
      self.ctx.logger.info("[UserRepository] ACTIVE: Connecting to database...")
      result = self.ctx.database.query("SELECT * FROM users")
      self.ctx.logger.info("[UserRepository] Fetched users: #{result}")

      -> {
        self.ctx.logger.info("[UserRepository] SUSPENDED/DISPOSED: Disconnecting from database...")
        nil
      }
    end
  end
end

Trellis.define_service("user_repository", UserRepository)

app = Trellis::Context.new
app.logger.info("--- Starting Reactive App ---")

user_repo = UserRepository.new(app)
sleep 20.milliseconds
app.logger.info("State after registering UserRepository: #{user_repo.ctx.node.state}")
puts ""

app.logger.info("--- Registering DatabaseService ---")
db = DatabaseService.new(app)
sleep 20.milliseconds
app.logger.info("State after registering DatabaseService: #{user_repo.ctx.node.state}")
puts ""

app.logger.info("--- Disposing DatabaseService ---")
db.ctx.node.dispose
sleep 20.milliseconds
app.logger.info("State after disposing DatabaseService: #{user_repo.ctx.node.state}")
puts ""

app.logger.info("--- Re-registering DatabaseService ---")
DatabaseService.new(app)
sleep 20.milliseconds
app.logger.info("State after re-registering DatabaseService: #{user_repo.ctx.node.state}")
puts ""

app.logger.info("--- Shutting Down Application ---")
app.node.dispose
