# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :id, :username, :name, :avatar_template, :distance, :last_seen_at,
             :is_virtual, :virtual_address, :location_type, :gender, :bio,
             :user_fields, :location_display_name, :is_online

  def id
    object[:user].id
  end

  def username
    object[:user].username
  end

  def name
    object[:user].name
  end

  def avatar_template
    object[:user].avatar_template
  end

    def distance
    object[:distance]
  end

  def last_seen_at
    object[:user].last_seen_at
  end

  def is_virtual
    object[:location].is_virtual || false
  end

  def virtual_address
    object[:location].virtual_address
  end

  def location_type
    object[:location].location_type || 'real'
  end

  def gender
    # 尝试从用户字段中获取性别信息
    user_fields_data = object[:user].user_fields || {}
    
    # 检查常见的性别字段名
    gender_value = user_fields_data['性别'] || 
                   user_fields_data['gender'] || 
                   user_fields_data['Gender'] ||
                   user_fields_data['sex'] ||
                   user_fields_data['Sex']
    
    # 如果用户字段中没有性别信息，尝试从自定义字段获取
    if gender_value.blank?
      gender_value = object[:user].custom_fields&.dig('gender')
    end
    
        gender_value
  end

  def bio
    object[:user].user_profile&.bio_raw
  end

  def user_fields
    # 只返回"属性"字段
    fields = {}
    
    # 获取用户字段数据
    if object[:user].user_fields.present?
      object[:user].user_fields.each do |key, value|
        next if value.blank?
        # 只包含"属性"字段
        if ['属性', 'attributes', 'Attributes'].include?(key)
          fields[key] = value
        end
      end
    end
    
    # 获取自定义字段中的属性
    if object[:user].custom_fields.present?
      object[:user].custom_fields.each do |key, value|
        next if value.blank?
        if ['属性', 'attributes', 'Attributes'].include?(key)
          fields[key] = value
        end
      end
    end
    
    fields
  end



  def location_display_name
    if is_virtual && virtual_address.present?
      virtual_address
    else
      "#{distance}km 外"
    end
  end

  def is_online
    # 判断用户是否在线（最近5分钟活跃）
    return false unless object[:user].last_seen_at
    object[:user].last_seen_at > 5.minutes.ago
  end
end 