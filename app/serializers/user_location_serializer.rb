# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :id, :username, :name, :avatar_template, :distance, :last_seen_at,
             :is_virtual, :virtual_address, :location_type, :gender, :bio,
             :user_fields, :location_display_name, :is_online, :debug_user_fields

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
      gender_value = object[:user].custom_fields&.dig('gender') ||
                     object[:user].custom_fields&.dig('性别')
    end
    
    # 标准化性别值
    return nil if gender_value.blank?
    
    case gender_value.to_s.downcase
    when '男', 'male', 'm', '1'
      'male'
    when '女', 'female', 'f', '2' 
      'female'
    else
      gender_value.to_s
    end
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
        # 排除性别字段，只包含属性相关字段
        next if ['性别', 'gender', 'Gender', 'sex', 'Sex'].include?(key)
        # 包含属性字段或其他非性别字段
        if ['属性', 'attributes', 'Attributes', '标签', 'tags', 'Tags', '兴趣', 'interests', 'hobby', '爱好'].include?(key)
          fields[key] = value
        end
      end
    end
    
    # 获取自定义字段中的属性
    if object[:user].custom_fields.present?
      object[:user].custom_fields.each do |key, value|
        next if value.blank?
        # 排除性别字段
        next if ['gender', '性别'].include?(key)
        # 包含属性相关字段
        if ['属性', 'attributes', 'Attributes', '标签', 'tags', 'Tags', '兴趣', 'interests', 'hobby', '爱好'].include?(key)
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

  def debug_user_fields
    # 返回所有用户字段用于调试
    debug_info = {}
    
    # 获取所有用户字段
    if object[:user].user_fields.present?
      debug_info[:user_fields] = object[:user].user_fields
    end
    
    # 获取所有自定义字段
    if object[:user].custom_fields.present?
      debug_info[:custom_fields] = object[:user].custom_fields
    end
    
    debug_info
  end
end 