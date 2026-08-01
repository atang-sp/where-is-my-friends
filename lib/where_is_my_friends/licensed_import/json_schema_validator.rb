# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class JsonSchemaValidator
      def self.validate!(value, schema)
        new.validate!(value, schema)
      end

      def validate!(value, schema)
        valid = valid_type?(value, schema.fetch(:type))
        valid &&= Array(schema[:enum]).include?(value) if schema.key?(:enum)
        valid &&= valid_object?(value, schema) if schema[:type] == "object"
        valid &&= valid_array?(value, schema) if schema[:type] == "array"
        raise AiGateway::InvalidResponse unless valid

        true
      end

      private

      def valid_type?(value, type)
        case type
        when "object"
          value.is_a?(Hash)
        when "array"
          value.is_a?(Array)
        when "string"
          value.is_a?(String)
        when "boolean"
          value == true || value == false
        else
          false
        end
      end

      def valid_object?(value, schema)
        properties = schema.fetch(:properties, {})
        required = schema.fetch(:required, [])
        return false unless required.all? { |key| value.key?(key) }
        if schema[:additionalProperties] == false
          return false unless (value.keys - properties.keys.map(&:to_s)).empty?
        end

        value.all? do |key, child|
          child_schema = properties[key.to_sym]
          child_schema.nil? || validate!(child, child_schema)
        rescue AiGateway::InvalidResponse
          false
        end
      end

      def valid_array?(value, schema)
        return true unless schema[:items]

        value.all? do |child|
          validate!(child, schema.fetch(:items))
        rescue AiGateway::InvalidResponse
          false
        end
      end
    end
  end
end
