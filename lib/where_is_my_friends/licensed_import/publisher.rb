# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class Publisher
      def publish!(title:, raw:, tags:, source_question_id: nil)
        custom_fields = {}
        if source_question_id
          custom_fields[
            "where_is_my_friends_licensed_import_source_id"
          ] = source_question_id
        end
        PostCreator.create!(
          Discourse.system_user,
          title: title,
          raw: raw,
          archetype: Archetype.default,
          category: SiteSetting.uncategorized_category_id,
          tags: tags,
          custom_fields: custom_fields
        )
      end

      def hide!(record)
        record.topic&.update!(visible: false)
      end
    end
  end
end
