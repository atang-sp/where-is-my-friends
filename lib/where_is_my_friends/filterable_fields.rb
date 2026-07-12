# frozen_string_literal: true

module WhereIsMyFriends
  class FilterableFields
    def self.resolve
      names =
        SiteSetting
          .where_is_my_friends_filterable_user_fields
          .to_s
          .split("|")
          .map(&:strip)
          .reject(&:blank?)
      return [] if names.empty?

      UserField
        .includes(:user_field_options)
        .where(name: names, field_type: "dropdown")
        .map do |field|
          {
            id: field.id,
            name: field.name,
            key: "user_field_#{field.id}",
            options: field.user_field_options.map(&:value),
          }
        end
    end
  end
end
