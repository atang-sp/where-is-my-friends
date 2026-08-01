# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class Publisher
      class MissingCategory < StandardError
      end

      def publish!(
        title:,
        raw:,
        tags:,
        source_type: "stack_exchange",
        source_question_id: nil
      )
        custom_fields = {}
        if source_question_id
          custom_fields[
            "where_is_my_friends_licensed_import_source_key"
          ] = "#{source_type}:#{source_question_id}"
          if source_type == "stack_exchange"
            custom_fields[
              "where_is_my_friends_licensed_import_source_id"
            ] = source_question_id
          end
        end
        PostCreator.create!(
          Discourse.system_user,
          title: title,
          raw: raw,
          archetype: Archetype.default,
          category: category.id,
          tags: tags,
          custom_fields: custom_fields
        )
      end

      def hide!(record)
        record.topic&.update!(visible: false)
      end

      def validate_configuration!
        category
        true
      end

      private

      def category
        category_id = SiteSetting.licensed_import_category_id.to_i
        result = Category.find_by(id: category_id, read_restricted: false)
        if result.blank? || result.id == SiteSetting.uncategorized_category_id
          raise MissingCategory
        end

        result
      end
    end
  end
end
