module Openapi
  class SwaggerRoot
    include Swagger::Blocks

    def self.build_specification(config)
      swagger_root do
        key :swagger,  '2.0'
        key :host,     ENV['HOST'] || 'localhost:3000'
        key :basePath, config[:base_path] || '/api'
        key :consumes, %w(application/json)
        key :produces, %w(application/json text/csv)
        key :schemes,  config[:base_path] || 'https'

        info do
          key :title,       config[:title] || 'Default'
          key :description, config[:description] || ''
          key :version,     config[:version] || '1.0'
        end

        config[:security_definitions].each do |name, security|
          security_definition name do
            key :type, security[:type]
            key :authorizationUrl, security[:authorization_url] if security[:authorization_url]
            key :flow, security[:flow] if security[:flow]
            scopes do
              security[:scopes].each do |scope, description|
                key scope, description
              end
            end if security[:scopes]
          end
        end

        config[:controllers].each do |controller|
          if controller.respond_to?(:openapi_collection_name)
            tag do
              key :name, controller.openapi_collection_name
            end
          else
            warn "#{controller.to_s} is not inhereted from a Openapi controller."
          end
        end
      end
    end
  end
end
