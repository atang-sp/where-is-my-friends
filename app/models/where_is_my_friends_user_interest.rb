# frozen_string_literal: true

class WhereIsMyFriendsUserInterest < ActiveRecord::Base
  belongs_to :user
  belongs_to :tag
  belongs_to :profile,
             class_name: "WhereIsMyFriendsInterestProfile",
             foreign_key: :user_id,
             primary_key: :user_id,
             inverse_of: :interests

  validates :tag_id, uniqueness: { scope: :user_id }
end
