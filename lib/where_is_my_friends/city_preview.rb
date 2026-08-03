# frozen_string_literal: true

module WhereIsMyFriends
  class CityPreview
    def initialize(user:, city:)
      @user = user
      @city = city
    end

    def call
      network =
        CityNetwork.new.preview(city: @city, exclude_user_id: @user.id)
      city = network[:city]
      local_topics =
        if city[:canonical]
          LocalTopics.new(user: @user, city_keys: [city[:city_key]]).call
        else
          []
        end

      network.merge(
        local_topics: local_topics,
        local_topic_compose_url:
          (
            if city[:canonical]
              LocalTopics.compose_url(city[:city_key])
            end
          )
      )
    end
  end
end
