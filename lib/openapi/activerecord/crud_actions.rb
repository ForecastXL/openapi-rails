module Openapi
  module ActiveRecord
    module CrudActions
      extend ActiveSupport::Concern

      included do
        respond_to :json
        respond_to :csv, only: %w(index)

        class_attribute :resource_class
        class_attribute :per_page

        ## Actions

        def index
          @chain = default_scope

          apply_scopes_to_chain!
          search_filter_chain!
          paginate_chain!
          set_index_headers!

          respond_to do |format|
            format.json { render json: { data: @chain.as_json(json_config) } }
            format.csv  { render csv: @chain }
          end
        end

        def show
          @object = find_object
          set_object_version!
          render json: { data: @object.as_json(json_config) }
        end

        def create
          @object = build_object

          if @object.save
            render json: { data: @object.as_json(json_config) }, status: :created

          else
            log_errors @object.errors
            render json: { errors: @object.errors } , status: :unprocessable_entity

          end
        end

        def update
          @object = find_object
          if @object.update_attributes(resource_params)
            render json: @object.as_json(json_config)

          else
            log_errors @object.errors
            render json: @object.errors, status: :unprocessable_entity

          end
        end

        def destroy
          @object = find_object

          if @object.destroy
            render nothing: true, status: :no_content

          else
            log_errors @object.errors
            render json: @object.errors, status: :unprocessable_entity

          end
        end

        def response_config
          config  = {}
          config[:only] = fields
          methods = params[:methods]

          if methods
            include_methods = methods.split(',').select do |method_name|
              method = method_name.to_sym
              resource_class.instance_methods(false).include?(method)
            end
            config[:methods] = include_methods unless include_methods.empty?
          end

          config
        end
        alias csv_config response_config
        alias json_config response_config

        ## Helpers

        def log_errors(errors)
          if Rails.env.development?
            logger.info "Errors:\n  #{errors.to_h}"
          end
        end

        # @return [Class]
        def resource_class
          @resource_class ||= self.class.resource_class || controller_to_class
        end

        # Extracts the corresponding class from the controller class.
        # @return [Class]
        def controller_to_class
          self.class.to_s[/[^:]+(?=Controller\z)/].classify.constantize
        end

        def default_scope
          resource_class
        end

        def find_object
          resource_class.find_by(id: params[:id])
        end

        def build_object
          resource_class.new(resource_params)
        end

        def support_version?
          @object.respond_to?(:undo, true)
        end

        def set_object_version!
          version = params[:version]
          if version && support_version? && version.to_i != @object.version
            @object.undo(nil, from: version.to_i + 1, to: @object.version)
            @object.version = version
          end
        end

        def apply_scopes_to_chain!
          @chain = apply_scopes(@chain)
        end

        def support_search?
          @chain.respond_to?(:search, true)
        end

        def search_filter_chain!
          query = params[:search]
          if query && support_search?
            normalized_query = query.to_s.downcase
            @chain = @chain.search(normalized_query, match: :all)
          end
        end

        #
        # FIELDS
        #
        # With the fields property the attributes to be returned be record can be limited.

        # @return [Array] with the fields to be returned. Will return the default fields if none specified.
        def fields
          @fields ||= params[:fields]&.split(',')&.keep_if { |e| e.in?(readable_fields) } || readable_fields
        end

        # The default fields
        #
        # @return [Array] with the fields the client is allowed to view.
        def readable_fields
          resource_class.openapi_readable_attributes
        end

        # @return [Array] with the fields to the client is allowed to edit.
        def writable_fields
          resource_class.openapi_writable_attributes
        end

        # @return [Array] with the fields the client is allowed to view but not to edit.
        def read_only_fields
          resource_class.openapi_read_only_attributes
        end

        #
        # PAGINATION
        #
        # NOTICE: The api will silently override missing, incorrect or unallowed pagination requests
        # from the client and continue the request using the nearest correct settings.

        # @return [Integer] with the number of the current page. Default is 1.
        def page
          @page ||= [params[:page]&.to_i || 1, 1].max
        end

        # The number of records to be returned.
        #
        # The client can set the number using the 'per_page' or 'limit' param, they're identical.
        # The client is not allowed to set the number lower then 1 since this would make no sense.
        # A maximum can be set that the client is allowed to go over. This default can be set for the
        # entire api and overwritten on a per resource basis.
        # If the client does not provide a number a default is used. This default can be set for the
        # entire api and overwritten on a per resource basis.
        #
        # @return [Integer] with the numbers of records to return.
        def per_page
          @per_page ||= [[params[:perPage]&.to_i || params[:limit]&.to_i || self.class.per_page, 50].compact.min, 1].max
        end

        # @return [Integer] with the offset to use in the sql query.
        def offset
          @offset ||= [params[:offset]&.to_i || (page - 1) * per_page, 0].max
        end

        # @return [Integer] with the total number of pages.
        def total_pages
          @total_pages ||= (total_count / per_page.to_f).ceil
        end

        # @return [Integer] with the number of records in the database within the given filters.
        def total_count
          @total_count ||= @chain.count
        end

        # @return [Integer, nil] with the number of the next page if present.
        def next_page
          page >= total_pages ? nil : page + 1
        end

        def paginate_chain!
          @chain = @chain.offset(offset).limit(per_page)
        end

        # Adds pagination information to the response headers.
        #
        # The total number of records is added.
        # The url to the next page is added if available.
        def set_index_headers!
          response.headers['X-Total-Count'] = total_count

          if next_page
            url = request.url.gsub("page=#{page}", "page=#{next_page}")
            response.headers['Link'] = "<#{url}>; rel=\"next\""
          end
        end

        def resource_params
          params.require(resource_request_name).permit(*writable_fields)
        end

        def resource_request_name
          resource_class.to_s.underscore.gsub(/\/|::/, '_')
        end
      end

      class_methods do
        def resource_class(name)
          self.resource_class = name
        end

        def per_page(number)
          self.per_page = number
        end
      end
    end
  end
end