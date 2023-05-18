# config/initializers/schema_middleware.rb

class SchemaMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    domain = request.host

    puts domain

    schema_name = determine_schema(domain)
    connect_to_schema(schema_name)

    @app.call(env)
  end

  private

  def determine_schema(domain)
    name = domain.split(".").first
    return "public" if name == "chyb" || name == "www" 
  end

  def connect_to_schema(schema_name)
    return unless schema_name

    ActiveRecord::Base.establish_connection(
      "#{Rails.env}_#{schema_name}".to_sym
    )
  end
end

Rails.application.config.middleware.use SchemaMiddleware
