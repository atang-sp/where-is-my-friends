# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicFeed
    # Responsible for creating a new dynamic post via Discourse's normal
    # NewPostManager pipeline, including pre-creation content validation and the
    # thread-local creation context used by hooks to stamp the WIMF custom field.
    class Publisher
      def initialize(viewer:, guardian:, category:, serializer:)
        @viewer = viewer
        @guardian = guardian
        @category = category
        @serializer = serializer
      end

      # Validates raw content, delegates to NewPostManager, and returns a hash
      # of { queued: bool, dynamic: serialized_hash? }.
      def create(raw:)
        validate_content!(raw)
        result =
          DynamicFeed.with_creation_context do
            NewPostManager.new(
              @viewer,
              :raw => raw.to_s,
              :title => DynamicFeed.title_for(raw),
              :category => @category.id,
              :archetype => Archetype.default,
              :guardian => @guardian,
              :cooking_options => DynamicFeed.plain_link_cooking_options,
              INTERNAL_CREATION_PARAM => true
            ).perform
          end

        unless result.success?
          raise InvalidContent, result.errors.full_messages.to_sentence
        end

        if result.post
          { queued: false, dynamic: @serializer.serialize_many([result.post.topic]).first }
        else
          { queued: true }
        end
      end

      private

      def validate_content!(raw)
        message = DynamicFeed.validation_message(raw, enforce_length: true)
        raise InvalidContent, message if message
      end
    end
  end
end
