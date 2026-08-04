# frozen_string_literal: true

module WhereIsMyFriends
  module DynamicPostValidator
    def stripped_length(post)
      return super unless dynamic_first_post?(post)

      StrippedLengthValidator.validate(
        post,
        :raw,
        post.raw,
        DynamicFeed::MIN_VISIBLE_CHARACTERS..SiteSetting.max_post_length,
        strip_uploads: SiteSetting.prevent_uploads_only_posts
      )
    end

    private

    def dynamic_first_post?(post)
      DynamicFeed.creating? ||
        (post.is_first_post? && DynamicFeed.dynamic?(post.topic))
    end
  end
end
