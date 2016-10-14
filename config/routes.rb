Openapi::Engine.routes.draw do
  Openapi.apis.each do |name, config|
    base_path = config[:base_path] || '/api'

    config[:controllers].each do |controller|
      if controller.respond_to?(:build_openapi_specification)
        controller.build_openapi_specification(base_path: base_path)
      else
        warn "#{controller} was given but does not inherit from an Openapi controller"
      end
    end

    name = name.to_s.titleize.remove(' ')
    root_klass_name = "#{name}SwaggerRootController"

    unless root_klass_name.in?(config[:controllers].map(&:to_s))
      klass = Object.const_set(root_klass_name, Class.new(Openapi::SwaggerRoot))
      klass.build_specification(config)
      config[:controllers].push(klass)
    end
  end
end
