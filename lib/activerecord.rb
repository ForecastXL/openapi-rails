require 'swagger/blocks/activerecord_schema_builder'
require 'openapi/activerecord/spec_builder'
require 'openapi/activerecord/crud_actions'

class ActiveRecord::Base
  class_attribute :_openapi_read_only, :_openapi_hidden

  class << self
    def openapi_read_only(*attributes)
      self._openapi_read_only = attributes
    end

    def openapi_read_only_attributes
      self._openapi_read_only || []
    end

    def openapi_hidden(*attributes)
      self._openapi_hidden = attributes
    end

    def openapi_hidden_attributes
      self._openapi_hidden || []
    end

    def openapi_writable_attributes
      openapi_attributes - openapi_hidden_attributes - openapi_read_only_attributes
    end

    def openapi_readable_attributes
      openapi_attributes - openapi_hidden_attributes
    end

    def openapi_attributes
      @openapi_attributes ||= columns.map { |column| column.name.to_sym }
    end
  end
end
