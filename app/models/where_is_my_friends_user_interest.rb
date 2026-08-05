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

# == Schema Information
#
# Table name: where_is_my_friends_user_interests
#
#  id         :bigint           not null, primary key
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  tag_id     :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  idx_wimf_user_interests_tag     (tag_id)
#  idx_wimf_user_interests_unique  (user_id,tag_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tag_id => tags.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
