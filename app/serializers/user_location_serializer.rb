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
    # 从用户字段和自定义字段中查找性别信息
    gender_value = nil
    
    # 检查所有用户字段中可能的性别值
    user_fields_data = object[:user].user_fields || {}
    user_fields_data.each do |key, value|
      next if value.blank?
      # 检查值是否像性别
      if ['男', '女', 'male', 'female', 'm', 'f'].include?(value.to_s.downcase)
        gender_value = value
        break
      end
    end
    
    # 如果用户字段中没有找到，检查自定义字段
    if gender_value.blank?
      custom_fields = object[:user].custom_fields || {}
      custom_fields.each do |key, value|
        next if value.blank?
        # 检查字段名包含性别相关词汇或值像性别
        if key.to_s.match(/gender|性别|sex/i) || ['男', '女', 'male', 'female', 'm', 'f'].include?(value.to_s.downcase)
          gender_value = value
          break
        end
      end
    end
    
    # 标准化性别值
    return nil if gender_value.blank?
    
    case gender_value.to_s.downcase
    when '男', 'male', 'm'
      'male'
    when '女', 'female', 'f'
      'female'
    else
      gender_value.to_s
    end
  end

  def bio
    object[:user].user_profile&.bio_raw
  end

  def user_fields
    # 返回所有非性别的用户字段作为属性
    fields = {}
    
    # 获取用户字段数据
    if object[:user].user_fields.present?
      object[:user].user_fields.each do |key, value|
        next if value.blank?
        # 排除看起来像性别的字段
        next if ['男', '女', 'male', 'female', 'm', 'f'].include?(value.to_s.downcase)
        # 添加所有其他字段，使用"字段#{key}"作为显示名
        fields["字段#{key}"] = value
      end
    end
    
    # 获取自定义字段中的属性（排除系统字段和性别字段）
    if object[:user].custom_fields.present?
      object[:user].custom_fields.each do |key, value|
        next if value.blank?
        # 排除系统字段和性别相关字段
        next if key.to_s.match(/^(user_field_|last_chat_channel_id|gender|性别)/i)
        # 排除看起来像性别的值
        next if ['男', '女', 'male', 'female', 'm', 'f'].include?(value.to_s.downcase)
        fields[key] = value
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