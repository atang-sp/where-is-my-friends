# frozen_string_literal: true

# name: where-is-my-friends
# about: Interest-based community introductions and city-first local member discovery
# version: 1.23.0
# authors: atang
# url: https://github.com/atang-sp/where-is-my-friends
# required_version: 2026.7.0-latest

enabled_site_setting :where_is_my_friends_enabled
add_admin_route(
  "where_is_my_friends.admin.ai_providers.title",
  "where-is-my-friends",
  { use_new_show_route: true }
)

register_asset "stylesheets/where-is-my-friends.scss"
register_svg_icon "plug"
register_svg_icon "floppy-disk"
register_svg_icon "plane"
register_svg_icon "tag"

require_relative "lib/where_is_my_friends/engine"

after_initialize do
  SeedFu.fixture_paths << Rails
    .root
    .join("plugins/where-is-my-friends/db/fixtures")
    .to_s

  Rails.application.config.filter_parameters |= %i[api_key token claim_token]

  require_relative "lib/where_is_my_friends/interest_visibility"
  require_relative "lib/where_is_my_friends/flying_chess"
  require_relative "lib/where_is_my_friends/flying_chess/claim_token"
  if PostRevisor.ancestors.exclude?(WhereIsMyFriends::DynamicPostRevisor)
    PostRevisor.prepend(WhereIsMyFriends::DynamicPostRevisor)
  end
  if PostValidator.ancestors.exclude?(WhereIsMyFriends::DynamicPostValidator)
    PostValidator.prepend(WhereIsMyFriends::DynamicPostValidator)
  end

  register_topic_custom_field_type(
    "where_is_my_friends_licensed_import_source_id",
    :integer
  )
  register_topic_custom_field_type(
    "where_is_my_friends_licensed_import_source_key",
    :string
  )
  register_topic_custom_field_type(
    WhereIsMyFriends::DynamicFeed::FIELD,
    :boolean
  )
  allow_new_queued_post_payload_attribute(
    WhereIsMyFriends::DynamicFeed::INTERNAL_CREATION_PARAM
  )

  on(:after_validate_topic) do |topic, _creator|
    dynamic_category_id =
      SiteSetting.where_is_my_friends_dynamics_category_id.to_i
    next if dynamic_category_id.zero?
    next unless topic.category_id == dynamic_category_id
    next if WhereIsMyFriends::DynamicFeed.creating?

    topic.errors.add(:base, I18n.t("where_is_my_friends.dynamics.unavailable"))
  end

  on(:before_create_topic) do |topic, creator|
    unless creator.opts[WhereIsMyFriends::DynamicFeed::INTERNAL_CREATION_PARAM]
      next
    end

    topic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD] = true
  end

  on(:before_create_post) do |post, _options|
    creating_dynamic = WhereIsMyFriends::DynamicFeed.creating?
    existing_dynamic =
      post.topic_id.present? &&
        WhereIsMyFriends::DynamicFeed.dynamic?(post.topic)
    next unless creating_dynamic || existing_dynamic

    post.cooking_options =
      WhereIsMyFriends::DynamicFeed.plain_link_cooking_options(
        post.cooking_options
      )
  end

  validate(:post, :validate_where_is_my_friends_dynamic_content) do
    next unless raw_changed?

    creating_dynamic = WhereIsMyFriends::DynamicFeed.creating?
    existing_dynamic =
      topic_id.present? && WhereIsMyFriends::DynamicFeed.dynamic?(topic)
    next unless creating_dynamic || existing_dynamic

    message =
      WhereIsMyFriends::DynamicFeed.validation_message(
        raw,
        enforce_length: creating_dynamic || post_number == 1
      )
    errors.add(:raw, message) if message
  end

  on(:before_post_process_cooked) do |document, post|
    next unless WhereIsMyFriends::DynamicFeed.dynamic?(post.topic)

    WhereIsMyFriends::DynamicFeed.disable_oneboxes!(document)
  end

  on(:post_edited) do |post|
    next unless post.is_first_post?
    next unless WhereIsMyFriends::DynamicFeed.dynamic?(post.topic)

    editor = User.find_by(id: post.last_editor_id)
    attributes = {}
    if post.previous_changes.key?("raw") || !editor&.staff?
      attributes[:title] = WhereIsMyFriends::DynamicFeed.title_for(post.raw)
    end
    post.topic.update!(attributes) if attributes.present?
    post.topic.tags.delete_all if post.topic.tags.exists?
  end

  on(:topic_tags_changed) do |topic, _payload|
    next unless WhereIsMyFriends::DynamicFeed.dynamic?(topic)

    topic.tags.delete_all
  end

  TopicQuery.add_custom_filter(
    :where_is_my_friends_without_dynamics
  ) do |result|
    result.where.not(
      id:
        TopicCustomField.where(
          name: WhereIsMyFriends::DynamicFeed::FIELD
        ).select(:topic_id)
    )
  end

  UserUpdater::OPTION_ATTR.push(:where_is_my_friends_notify_city)
  UserUpdater::OPTION_ATTR.push(:where_is_my_friends_notify_nearby)
  UserUpdater::OPTION_ATTR.push(
    :where_is_my_friends_accept_practice_invitations
  )
  add_to_serializer(:user_option, :where_is_my_friends_notify_city) do
    object.where_is_my_friends_notify_city
  end
  add_to_serializer(:user_option, :where_is_my_friends_notify_nearby) do
    object.where_is_my_friends_notify_nearby
  end
  add_to_serializer(
    :user_option,
    :where_is_my_friends_accept_practice_invitations
  ) { object.where_is_my_friends_accept_practice_invitations }
  UserUpdater::OPTION_ATTR.push(:where_is_my_friends_accept_user_tags)
  add_to_serializer(:user_option, :where_is_my_friends_accept_user_tags) do
    object.where_is_my_friends_accept_user_tags
  end

  add_to_serializer(:user_card, :where_is_my_friends_city) do
    UserLocation.discoverable.find_by(user_id: object.id)&.city
  end

  add_to_serializer(:user, :where_is_my_friends_city) do
    UserLocation.discoverable.find_by(user_id: object.id)&.city
  end

  add_to_serializer(:user, :where_is_my_friends_flying_chess) do
    if WhereIsMyFriends::FlyingChess.achievements_enabled?
      profile = WhereIsMyFriendsFlyingChessProfile.find_by(user: object)
      if profile&.visible_to?(scope.user)
        WhereIsMyFriendsFlyingChessProfileSerializer.new(
          profile,
          scope: scope,
          root: false
        ).as_json
      end
    end
  end

  add_to_serializer(
    :current_user,
    :where_is_my_friends_interest_onboarding_state
  ) { WhereIsMyFriends::InterestVisibility.onboarding_state(object) }

  add_to_serializer(:user_card, :where_is_my_friends_public_interests) do
    WhereIsMyFriends::InterestVisibility.public_interests(
      object,
      guardian: scope
    )
  end

  add_to_serializer(
    :user_card,
    :where_is_my_friends_practice_invitation_interests
  ) do
    if scope.user
      WhereIsMyFriends::PracticeInvitationEligibility
        .new(sender: scope.user, recipient: object)
        .public_common_interests
        .map { |tag| { id: tag.id, name: tag.name } }
    else
      []
    end
  end

  add_to_serializer(:user, :where_is_my_friends_public_interests) do
    WhereIsMyFriends::InterestVisibility.public_interests(
      object,
      guardian: scope
    )
  end

  add_to_serializer(:topic_view, :where_is_my_friends_dynamic) do
    WhereIsMyFriends::DynamicFeed.dynamic?(object.topic)
  end

  add_to_serializer(
    :user,
    :where_is_my_friends_practice_invitation_interests
  ) do
    if scope.user
      WhereIsMyFriends::PracticeInvitationEligibility
        .new(sender: scope.user, recipient: object)
        .public_common_interests
        .map { |tag| { id: tag.id, name: tag.name } }
    else
      []
    end
  end

  add_to_serializer(:user_card, :where_is_my_friends_user_tags) do
    if scope.user && WhereIsMyFriends::UserTagVisibility.feature_enabled?
      WhereIsMyFriends::UserTagVisibility.public_tags_for(
        object,
        viewer: scope.user
      )
    else
      []
    end
  end

  add_to_serializer(:user, :where_is_my_friends_user_tags) do
    if scope.user && WhereIsMyFriends::UserTagVisibility.feature_enabled?
      WhereIsMyFriends::UserTagVisibility.public_tags_for(
        object,
        viewer: scope.user
      )
    else
      []
    end
  end

  on(:user_destroyed) do |user|
    WhereIsMyFriendsFlyingChessCompletion.where(user_id: user.id).delete_all
    WhereIsMyFriendsFlyingChessProfile.where(user_id: user.id).delete_all
  end

  on_enabled_change do |old_value, new_value|
    next if old_value == new_value

    Jobs.enqueue(Jobs::WhereIsMyFriendsSynchronizeFlyingChessBadges)
  end

  on(:site_setting_changed) do |name, old_value, new_value|
    next if old_value == new_value
    if name.to_sym != :where_is_my_friends_flying_chess_achievements_enabled
      next
    end

    Jobs.enqueue(Jobs::WhereIsMyFriendsSynchronizeFlyingChessBadges)
  end

  on(:where_is_my_friends_location_saved) do |user|
    badge = Badge.find_by(name: "Local Explorer")
    BadgeGranter.grant(badge, user) if badge&.enabled
  end

  on(:post_created) do |post|
    next unless WhereIsMyFriends::LocalTopics.local_topic?(post.topic)

    WhereIsMyFriendsEvent.create!(
      user_id: post.user_id,
      event_name: "local_topic_interacted"
    )
  rescue ActiveRecord::RecordInvalid
    # Analytics must never block posting.
  end

  # Render the Discourse application for the client route, then mount the JSON API.
  Discourse::Application.routes.append do
    unless Discourse.plugins_by_name["discourse-plugin-matching"]
      get "/practice-matching",
          to: redirect("/where-is-my-friends/interests", status: 302)
    end

    get "/where-is-my-friends.json" => "where_is_my_friends/locations#index",
        :as => "where_is_my_friends_data"
    get "/where-is-my-friends" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    get "/where-is-my-friends/interests" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    get "/where-is-my-friends/dynamics" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    get "/where-is-my-friends/tags" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    get "/where-is-my-friends/flying-chess" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    get "/admin/plugins/where-is-my-friends/ai-providers" =>
          "admin/plugins#show",
        :defaults => {
          plugin_id: "where-is-my-friends"
        },
        :constraints => AdminConstraint.new
    mount ::WhereIsMyFriends::Engine,
          at: "/where-is-my-friends",
          as: "where_is_my_friends_engine"
  end
end
