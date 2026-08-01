# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class PublicationTags
      SP_THEMES = %w[spanking discipline aftercare tools].freeze

      def self.for(theme)
        tags = [translate("tags.curated"), translate("tags.safety")]
        tags << translate("tags.sp_education") if SP_THEMES.include?(theme)
        tags
      end

      def self.translate(key)
        I18n.t("where_is_my_friends.licensed_import.#{key}", locale: :zh_CN)
      end
      private_class_method :translate
    end
  end
end
