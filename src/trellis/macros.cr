# src/trellis/macros.cr
module Trellis
  macro define_service(name, type)
    class ::Trellis::Context
      def {{name.id}} : {{type.id}}
        result = self.reflect.get({{name.id.stringify}}, strict: true)
        if result.nil?
          raise ::Trellis::ServiceNotInjectedError.new("Service not injected or inactive: " + {{name.id.stringify}})
        end
        result.as({{type.id}})
      end

      def {{name.id}}? : {{type.id}}?
        result = self.reflect.get({{name.id.stringify}}, strict: true)
        result.as?({{type.id}})
      end
    end
  end
end
