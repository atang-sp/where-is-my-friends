# frozen_string_literal: true

require_relative "dynamic_feed/serializer"
require_relative "dynamic_feed/queries"
require_relative "dynamic_feed/publisher"
require_relative "dynamic_feed/reactor"

module WhereIsMyFriends
  # Lightweight orchestrator for the DynamicFeed domain.
  #
  # Instance methods are thin delegators to four focused sub-components:
  #   DynamicFeed::Queries    — read-side feed queries
  #   DynamicFeed::Publisher  — content creation via NewPostManager
  #   DynamicFeed::Reactor    — reactions, rate-limits, notification sync
  #   DynamicFeed::Serializer — Topic/Post → Hash conversion
  #
  # Class-level helpers (title generation, content validation, creation-context
  # management) remain here because they are stateless utilities shared by
  # hooks, specs, and the sub-components themselves.
  class DynamicFeed
    FIELD = "where_is_my_friends_dynamic"
    PAGE_SIZE = 20
    DISCOVERY_PAGE_SIZE = 10
    RECENT_LIMIT = 3
    RECENT_WINDOW = 30.days
    MIN_VISIBLE_CHARACTERS = 8
    MAX_VISIBLE_CHARACTERS = 500
    CREATION_CONTEXT_KEY = :where_is_my_friends_dynamic_creation
    INTERNAL_CREATION_PARAM = :where_is_my_friends_dynamic
    MEDIA_PATTERN =
      %r{
      upload://|
      /uploads/|
      !\[[^\]]*\]\s*(?:\(|\[)|
      \[img(?:=[^\]]+)?\]|
      <\s*(?:img|picture|video|audio|source|object|embed|iframe|svg)\b
    }ix
    COOKED_MEDIA_SELECTOR =
      "img:not(.emoji), picture, video, audio, source, object, embed, iframe, svg"

    class InvalidContent < StandardError
    end

    class InvalidReaction < StandardError
    end

    # -------------------------------------------------------------------------
    # Construction — build sub-components and validate availability.
    # -------------------------------------------------------------------------

    def initialize(viewer:, guardian: nil)
      @viewer = viewer
      @guardian = guardian || Guardian.new(viewer)
      ensure_available!

      @serializer = Serializer.new(viewer: @viewer)
      @queries    = Queries.new(viewer: @viewer, guardian: @guardian, category: @category, serializer: @serializer)
      @publisher  = Publisher.new(viewer: @viewer, guardian: @guardian, category: @category, serializer: @serializer)
      @reactor    = Reactor.new(viewer: @viewer, guardian: @guardian, queries: @queries)
    end

    # -------------------------------------------------------------------------
    # Query delegation
    # -------------------------------------------------------------------------

    def feed(username:, before_id: nil)
      @queries.feed(username: username, before_id: before_id)
    end

    def recent
      @queries.recent
    end

    def discover(before_id: nil, limit: nil)
      @queries.discover(before_id: before_id, limit: limit)
    end

    def latest_by_user_ids(user_ids)
      @queries.latest_by_user_ids(user_ids)
    end

    # -------------------------------------------------------------------------
    # Publisher delegation
    # -------------------------------------------------------------------------

    def create(raw:)
      @publisher.create(raw: raw)
    end

    # -------------------------------------------------------------------------
    # Reactor delegation
    # -------------------------------------------------------------------------

    def react(topic_id:, kind:)
      @reactor.react(topic_id: topic_id, kind: kind)
    end

    def unreact(topic_id:)
      @reactor.unreact(topic_id: topic_id)
    end

    # -------------------------------------------------------------------------
    # Class-level stateless utilities (shared by hooks and sub-components)
    # -------------------------------------------------------------------------

    def self.dynamic?(topic)
      ActiveModel::Type::Boolean.new.cast(topic&.custom_fields&.[](FIELD))
    end

    def self.creating?
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] == true
    end

    def self.with_creation_context
      previous = ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY]
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] = previous
    end

    def self.visible_text(raw, document: cooked_document(raw))
      document
        .css("img.emoji")
        .each do |emoji|
          replacement = emoji["title"].presence || emoji["alt"].presence || ""
          emoji.replace(Nokogiri::XML::Text.new(replacement, document))
        end
      document.text.gsub(/\s+/, " ").strip
    end

    def self.title_for(raw, at: Time.current)
      maximum = SiteSetting.max_topic_title_length
      suffix = "#{at.utc.strftime("%y%m%d%H%M%S")}-#{SecureRandom.hex(3)}"
      separator = " · "
      return suffix.last(maximum) if maximum <= suffix.length + separator.length

      summary_limit = [maximum - suffix.length - separator.length, 100].min
      summary = visible_text(raw).truncate(summary_limit, omission: "")
      "#{summary}#{separator}#{suffix}"
    end

    def self.disable_oneboxes!(document)
      document
        .css("a.onebox, a.inline-onebox-loading")
        .each do |link|
          link.remove_class("onebox")
          link.remove_class("inline-onebox-loading")
        end
    end

    def self.plain_link_cooking_options(options = nil)
      (options || {}).deep_symbolize_keys.deep_merge(
        features: {
          onebox: false
        }
      )
    end

    def self.validation_message(raw, enforce_length:)
      if raw.to_s.match?(MEDIA_PATTERN) ||
           Upload.extract_upload_ids(raw.to_s).present?
        return I18n.t("where_is_my_friends.dynamics.media_not_allowed")
      end

      document = cooked_document(raw)
      if document.css(COOKED_MEDIA_SELECTOR).present?
        return I18n.t("where_is_my_friends.dynamics.media_not_allowed")
      end

      if enforce_length
        length = visible_text(raw, document: document).grapheme_clusters.length
        unless length.between?(MIN_VISIBLE_CHARACTERS, MAX_VISIBLE_CHARACTERS)
          return I18n.t("where_is_my_friends.dynamics.invalid_length")
        end
      end

      nil
    end

    def self.cooked_document(raw)
      Nokogiri::HTML5.fragment(
        PrettyText.cook(raw.to_s, features: { onebox: false })
      )
    end

    private

    # -------------------------------------------------------------------------
    # Internal helpers — availability guard and category validation
    # -------------------------------------------------------------------------

    def ensure_available!
      raise Discourse::NotFound unless SiteSetting.where_is_my_friends_enabled
      unless SiteSetting.where_is_my_friends_dynamics_enabled
        raise Discourse::NotFound
      end

      @category =
        Category.find_by(
          id: SiteSetting.where_is_my_friends_dynamics_category_id.to_i
        )
      raise Discourse::NotFound unless valid_category?(@category)
      raise Discourse::NotFound unless @guardian.can_see?(@category)
    end

    def valid_category?(category)
      return false unless category&.read_restricted?
      return false if category.minimum_required_tags.to_i.nonzero?

      members_group_id = Group::AUTO_GROUPS[:trust_level_0]
      full_permission = CategoryGroup.permission_types[:full]
      permissions = category.category_groups.pluck(:group_id, :permission_type)
      return false unless permissions == [[members_group_id, full_permission]]

      SiteSetting
        .default_categories_muted
        .split("|")
        .map(&:to_i)
        .include?(category.id)
    end
  end
end
