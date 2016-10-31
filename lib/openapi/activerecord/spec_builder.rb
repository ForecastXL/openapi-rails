module Openapi
  module ActiveRecord
    module SpecBuilder
      extend ActiveSupport::Concern

      CRUD_ACTIONS = %w(index create show update destroy).freeze

      included do
        include Swagger::Blocks

        class_attribute :openapi_collection_name
        class_attribute :openapi_resource_name
        class_attribute :openapi_resource_class
        class_attribute :openapi_except_actions
        class_attribute :openapi_relative_path

        class_attribute :openapi_base_path
      end

      class_methods do
        def openapi_config(options)
          self.openapi_collection_name = options[:collection_name]
          self.openapi_resource_name   = options[:resource_name]
          self.openapi_resource_class  = options[:resource_class]
          self.openapi_except_actions  = options[:except_actions]
          self.openapi_relative_path   = options[:relative_path]
        end

        def build_openapi_specification(options)
          self.openapi_base_path = options[:base_path]

          self.openapi_relative_path ||=
            ('/' + to_s.remove(/Controller$/).gsub('::', '/').underscore).remove(openapi_base_path)

          self.openapi_except_actions  ||= []
          self.openapi_collection_name ||= to_s[/[^:]+(?=Controller\z)/]
          self.openapi_resource_name   ||= openapi_collection_name.singularize
          self.openapi_resource_class  ||= self&.resource_class || openapi_resource_name.constantize

          # Before database actions such as create, migrate, drop, etc. the routes are loaded and
          # that means the openapi_definitions will try to lookup the columns of the tables to get
          # their information. If a table does not yet exist it will crash. Therefore we test if
          # it is already created or not.
          return unless ::ActiveRecord::Base.connection.data_source_exists?(openapi_resource_class.table_name)

          build_openapi_definitions
          build_openapi_paths
        end

        def build_openapi_paths
          routes = Openapi::RoutesParser.new(self).routes
          build_crud_specification(routes)

          if Rails.env.development?
            warn_on_undocumented_actions(routes)
          end
        end

        def build_openapi_definitions
          collection_name = openapi_collection_name
          resource_class = openapi_resource_class
          resource_name = openapi_resource_name
          resource_property_name = resource_name.underscore.to_sym

          swagger_schema resource_name do
            activerecord_build_model_schema(resource_class)

            resource_class.reflect_on_all_associations.each do |association|
              relation_type = if association.respond_to?(:delegate_reflection)
                association.delegate_reflection.class.to_s
              else
                association.class.to_s
              end

              begin
                embedded_resource_class = association.klass
              rescue NameError
                next
              end

              if relation_type&.include?('Many')
                property association.name.to_s, type: :array do
                  items do
                    activerecord_build_model_schema(embedded_resource_class)
                  end
                end
              else
                property association.name.to_s.singularize, type: :object do
                  activerecord_build_model_schema(embedded_resource_class)
                end
              end
            end
          end

          swagger_schema "#{resource_name}Input" do
            property resource_property_name, type: :object do
              activerecord_build_model_schema(resource_class, false)

              if resource_class.nested_attributes_options?
                resource_class.nested_attributes_options.each do |key, options|
                  next if options[:update_only]

                  property key, type: :object do
                    activerecord_build_model_schema(key.to_s.classify.constantize)
                  end
                end
              end
            end
          end
        end

        def build_crud_specification(routes)
          name        = openapi_resource_name
          sym_name    = name.underscore.to_sym
          plural_name = openapi_collection_name
          path        = openapi_relative_path
          scopes      = try(:scopes_configuration) || []
          actions     = routes.map { |r| r[2] }.uniq
          json_mime   = %w(application/json)

          include_index   = actions.include?('index') && openapi_except_actions.exclude?('index')
          include_create  = actions.include?('create') && openapi_except_actions.exclude?('create')
          include_show    = actions.include?('show') && openapi_except_actions.exclude?('show')
          include_update  = actions.include?('update') && openapi_except_actions.exclude?('update')
          include_destroy = actions.include?('destroy') && openapi_except_actions.exclude?('destroy')

          include_collection_actions = include_index || include_create
          include_resource_actions = include_show || include_update || include_destroy

          support_search = openapi_resource_class.instance_methods(false).include?(:search)

          if include_collection_actions
            swagger_path path do

              if include_index
                operation :get do
                  key :tags,        [plural_name]
                  key :summary,     'Index'
                  key :operationId, "index#{plural_name}"
                  key :produces,    json_mime

                  parameter do
                    key :name,        :page
                    key :description, 'Page number'
                    key :type,        :integer
                    key :format,      :int32
                    key :in,          :query
                    key :required,    false
                  end

                  parameter do
                    key :name,        :perPage
                    key :description, 'Items per page'
                    key :type,        :integer
                    key :format,      :int32
                    key :in,          :query
                    key :required,    false
                  end

                  parameter do
                    key :name,     :fields
                    key :in,       :query
                    key :required, false
                    key :description, 'Return exact model fields'
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  parameter do
                    key :name,        :methods
                    key :description, 'Include model methods'
                    key :in,          :query
                    key :required,    false
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  if support_search
                    parameter do
                      key :name,        :search
                      key :description, 'Search query string'
                      key :type,        :string
                      key :in,          :query
                      key :required,    false
                    end
                  end

                  scopes.each do |k, config|
                    scope_name = config[:as]
                    scope_type = config[:type]

                    if scope_type == :default
                      scope_type = :string
                    end

                    parameter do
                      key :name,     scope_name
                      key :type,     scope_type
                      key :in,       :query
                      key :required, false

                      if scope_type == :integer
                        key :format, :int32
                      end
                    end
                  end

                  response 200 do
                    key :description, 'Success'
                    schema type: :array do
                      items do
                        key :'$ref', name
                      end
                    end
                  end
                end
              end

              if include_create
                operation :post do
                  key :tags,        [plural_name]
                  key :summary,     'Create'
                  key :operationId, "create#{plural_name}"
                  key :produces,    json_mime

                  parameter do
                    key :name,     "body{#{sym_name}}"
                    key :in,       :body
                    key :required, true
                    schema do
                      key :'$ref', "#{name}Input"
                    end
                  end

                  parameter do
                    key :name,     :fields
                    key :in,       :query
                    key :required, false
                    key :description, 'Return exact model fields'
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  parameter do
                    key :name,        :methods
                    key :description, 'Include model methods'
                    key :in,          :query
                    key :required,    false
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  response 201 do
                    key :description, 'Success'
                    schema do
                      key :'$ref', name
                    end
                  end
                end
              end
            end
          end

          if include_resource_actions
            swagger_path "#{path}/{id}" do

              if include_show
                operation :get do
                  key :tags,        [plural_name]
                  key :summary,     'Show'
                  key :operationId, "show#{name}ById"
                  key :produces,    json_mime

                  parameter do
                    key :name,     :id
                    key :type,     :string
                    key :in,       :path
                    key :required, true
                  end

                  parameter do
                    key :name,     :fields
                    key :in,       :query
                    key :required, false
                    key :description, 'Return exact model fields'
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  parameter do
                    key :name,        :methods
                    key :description, 'Include model methods'
                    key :in,          :query
                    key :required,    false
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  response 200 do
                    key :description, 'Success'
                    schema do
                      key :'$ref', name
                    end
                  end
                end
              end

              if include_update
                operation :put do
                  key :tags,        [plural_name]
                  key :summary,     'Update'
                  key :operationId, "update#{name}"
                  key :produces,    json_mime

                  parameter do
                    key :name,     :id
                    key :type,     :string
                    key :in,       :path
                    key :required, true
                  end

                  parameter do
                    key :name,     :fields
                    key :in,       :query
                    key :required, false
                    key :description, 'Return exact model fields'
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  parameter do
                    key :name,        :methods
                    key :description, 'Include model methods'
                    key :in,          :query
                    key :required,    false
                    key :type,        :array
                    items do
                      key :type, :string
                    end
                  end

                  parameter do
                    key :name,     "body{#{sym_name}}"
                    key :in,       :body
                    key :required, true
                    schema do
                      key :'$ref', "#{name}Input"
                    end
                  end

                  response 200 do
                    key :description, 'Success'
                    schema do
                      key :'$ref', name
                    end
                  end
                end
              end

              if include_destroy
                operation :delete do
                  key :tags,        [plural_name]
                  key :summary,     'Destroy'
                  key :operationId, "destroy#{name}"

                  parameter do
                    key :name,     :id
                    key :type,     :string
                    key :in,       :path
                    key :required, true
                  end

                  response 204 do
                    key :description, 'Success'
                  end
                end
              end
            end
          end
        end

        def warn_on_undocumented_actions(routes)
          custom_routes = routes.select { |r| !CRUD_ACTIONS.include?(r[2]) }
          no_spec_methods = custom_routes.select do |route|
            method = route[0].to_sym
            path = route[1].remove(openapi_base_path)
            path_sym = path.gsub(/:(\w+)/, '{\1}').to_sym

            ! action_specification_exists?(method, path_sym)
          end

          unless no_spec_methods.empty?
            routes = no_spec_methods.map do |r|
              "  #{r[0].upcase} #{r[1]}"
            end.join("\n")

            puts "\n#{self} misses specification for:\n#{routes}\n\n"
          end
        end

        def action_specification_exists?(method, path)
          swagger_nodes = self.send(:_swagger_nodes)
          node_map = swagger_nodes[:path_node_map]

          node_map.has_key?(path) && node_map[path].data.has_key?(method)
        end
      end
    end
  end
end
