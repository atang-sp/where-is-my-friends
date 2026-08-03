# frozen_string_literal: true

module WhereIsMyFriends
  module DynamicPostRevisor
    PROTECTED_MEMBER_FIELDS = %i[title category_id tags].freeze

    def revise!(editor, fields, opts = {})
      if dynamic_post?
        post = instance_variable_get(:@post)
        post.cooking_options =
          WhereIsMyFriends::DynamicFeed.plain_link_cooking_options(
            post.cooking_options
          )
      end
      if !editor&.staff? && dynamic_first_post?
        fields = fields.with_indifferent_access.except(*PROTECTED_MEMBER_FIELDS)
      end

      super(editor, fields, opts)
    end

    private

    def dynamic_first_post?
      post = instance_variable_get(:@post)
      post&.is_first_post? && dynamic_post?
    end

    def dynamic_post?
      topic = instance_variable_get(:@topic)
      WhereIsMyFriends::DynamicFeed.dynamic?(topic)
    end
  end
end
