require 'swagger/blocks/activerecord_schema_builder'
require 'openapi/activerecord/spec_builder'
require 'openapi/activerecord/crud_actions'

# Extend the ActiveRecord::Base to include methods to describe which attributes are accessible
# through the API.
class ActiveRecord::Base
  class_attribute :_openapi_read_only, :_openapi_write_only, :_openapi_hidden, :_openapi_methods

  class << self
    def openapi_read_only(*attributes)
      self._openapi_read_only = attributes
    end

    def openapi_read_only_attributes
      _openapi_read_only || []
    end

    def openapi_write_only(*attributes)
      self._openapi_write_only = attributes
    end

    def openapi_write_only_attributes
      _openapi_write_only || []
    end

    def openapi_hidden(*attributes)
      self._openapi_hidden = attributes
    end

    def openapi_hidden_attributes
      _openapi_hidden || []
    end

    def openapi_writable_attributes
      openapi_attributes + openapi_write_only_attributes - openapi_hidden_attributes -
        openapi_read_only_attributes
    end

    def openapi_readable_attributes
      openapi_attributes - openapi_hidden_attributes
    end

    def openapi_attributes
      @openapi_attributes ||= columns.map { |column| column.name.to_sym }
    end

    def openapi_methods(*attributes)
      self._openapi_methods = attributes
    end

    def openapi_methods_attributes
      _openapi_methods || []
    end
  end
end
