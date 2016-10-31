module Swagger
  module Blocks
    module SchemaBuilder
      extend ActiveSupport::Concern

      # Builds the schema based on the information within the ActiveRecord classes.
      #
      # @param model_class [ActiveRecord] the class to render the schema for.
      # @param include_only_required_fields [Boolean] instructing if the optional fields need to be
      #        included in the output.
      def activerecord_build_model_schema(model_class, include_only_required_fields = false)
        required_fields = activerecord_get_required_fields(model_class)
        hidden_fields = model_class.openapi_hidden_attributes
        read_only_fields = model_class.openapi_read_only_attributes

        # Adds an Array with required fields to the resource
        key :required, required_fields - hidden_fields

        model_class.columns.each do |column|
          name = column.name.to_sym

          next if name.in?(hidden_fields)
          next if include_only_required_fields && required_fields.exclude?(name)

          property name do
            # The order is important. The validations have to be last because of the only_integer
            # validation.
            type_format_default_items(column)
            validations(model_class, column)
            key :readOnly, true if name.in?(read_only_fields)
          end
        end
      end

      # @param model_class [ActiveRecord] class for which to determine the required fields.
      # @return [Array <Symbol>] with required fields.
      def activerecord_get_required_fields(model_class)
        model_class.validators.
          select { |v| v.class == ActiveRecord::Validations::PresenceValidator }.
          map(&:attributes).flatten
      end

      def type_format_default_items(field)
        case field.type
        when :string
          if field.array
            key :type, :array
            key :default, field.default.tr('{}', '[]') if field.default
            items do
              key :type, :string
            end
          else
            key :type, :string
            key :default, field.default if field.default
          end
        when :text
          key :type, :string
          key :default, field.default if field.default
        when :integer
          if field.array
            key :type, :array
            key :default, field.default.tr('{}', '[]') if field.default
            items do
              key :type, :integer
            end
          else
            key :type, :integer
            key :default, field.default.to_i if field.default
          end
        when :decimal
          key :type, :double
          key :default, field.default.to_f if field.default
        when :hstore
          key :type, :object
          key :default, field.default if field.default
          items do
            key :type, :string
          end
        when :boolean
          key :type, :boolean
          key :default, to_bool(field.default) unless field.default.nil?
        when :date
          key :type, :date
          key :default, field.default.to_s if field.default
        when :datetime, :timestamp
          key :type, :string
          key :format, :'date-time'
          key :default, field.default.to_s if field.default
        when :time
          key :type, :string
          key :format, :'time'
          key :default, field.default.to_s if field.default
        when :'BSON::ObjectId', :uuid
          key :type, :string
          key :format, :uuid
          key :default, field.default if field.default
        else
          warn "The attribute type could not be determined. It will be treated as String."
          key :type, :string
        end
      end

      # Adds validation keys based on the ActiveModel/Record validations found in the class.
      def validations(model_class, field)
        model_class.validators_on(field.name).each do |validator|
          # Skip any validations with conditions since we cannot predicate their effect on the api.
          next if validator.options.keys.any? { |k| k.in?(%i(unless if scope)) }

          case validator.class.to_s[/[a-z]+\z/i]
          when 'InclusionValidator'
            key :required, !validator.options[:allow_blank] || !validator.options[:allow_nil]
            key :enum, validator.options[:in]
          when 'PresenceValidator'
            key :required, true
          when 'UniquenessValidator'
            key :uniqueItems, true
          when 'FormatValidator'
            key :pattern, validator.options[:with]
          when 'NumericalityValidator'
            validator.options.each do |option, value|
              case option
              when :greater_than_or_equal_to
                key :minimum, value
              when :greater_than
                key :minimum, value
                key :exclusiveMinimum, true
              when :less_than_or_equal_to
                key :maximum, value
              when :less_than
                key :maximum, value
                key :exclusiveMaximum, true
              when :only_integer
                # This validation might override the type as set by the type_format_default_items
                # function. It will make sure that a decimal database field is treated as an integer
                # field by the api.
                key :type, :integer if value
              end
            end
          when 'ExclusionValidator', 'AbsenceValidator'
            # For these standard validators no equivalent in the openapi spec is (yet) known.
          when 'LengthValidator'
            validator.options.each do |option, value|
              key :minLength, value if option == :minimum || option == :is
              key :maxLength, value if option == :maximum || option == :is
            end
          else
            # Custom validator.
            # warn "#{validator} is not converted into api specs."
          end
        end
      end

      # @param value [*] takes any value.
      # @return [Boolean] with true or false depending on what is mostly expected.
      def to_bool(value)
        case value
        when true, false
          value
        when String
          value.downcase == 'true' || value == '1'
        when Integer
          value.positive?
        when nil
          false
        else
          true
        end
      end
    end
  end
end
