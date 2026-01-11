# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :id, :username, :name, :avatar_template, :distance, :last_seen_at,
             :is_virtual, :virtual_address, :location_type, :gender, :bio,
             :user_fields, :location_display_name, :is_online,
             :location_source, :location_accuracy, :is_low_accuracy

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
      if gender_like_value?(value)
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
        if key.to_s.match(/gender|性别|sex/i) || gender_like_value?(value)
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
    # 返回所有非性别的用户字段作为属性（带字段名）
    fields = {}
    user_field_names = user_field_name_map
    
    # 获取用户字段数据
    if object[:user].user_fields.present?
      object[:user].user_fields.each do |key, value|
        next if value.blank?
        # 排除看起来像性别的字段
        next if gender_like_value?(value)
        # 添加所有其他字段，优先使用用户自定义字段名称
        label = user_field_names[key.to_i].presence || "字段#{key}"
        fields[label] = normalize_field_value(value)
      end
    end
    
    # 获取自定义字段中的属性（排除系统字段和性别字段）
    if object[:user].custom_fields.present?
      object[:user].custom_fields.each do |key, value|
        next if value.blank?
        # 排除系统字段和性别相关字段
        next if key.to_s.match(/^(user_field_|last_chat_channel_id|gender|性别)/i)
        # 排除看起来像性别的值
        next if gender_like_value?(value)
        label = key.to_s.tr("_", " ").strip
        fields[label] = normalize_field_value(value)
      end
    end
    
    fields
  end



  def location_display_name
    distance_text = distance.present? ? "#{distance}km 外" : nil

    if is_virtual && virtual_address.present?
      distance_text ? "#{virtual_address} · #{distance_text}" : virtual_address
    else
      distance_text.to_s
    end
  end

  def is_online
    # 判断用户是否在线（最近5分钟活跃）
    return false unless object[:user].last_seen_at
    object[:user].last_seen_at > 5.minutes.ago
  end
  
  def location_source
    object[:location].location_source || 'unknown'
  end
  
  def location_accuracy
    object[:location].location_accuracy
  end
  
  def is_low_accuracy
    # IP定位或精度超过1000米视为低精度
    return false if is_virtual
    return true if location_source == 'ip'
    return true if location_accuracy.present? && location_accuracy > 1000
    location_source == 'unknown'
  end

  private

  def user_field_name_map
    @user_field_name_map ||= UserField.pluck(:id, :name).to_h
  end

  def normalize_field_value(value)
    return value.join(", ") if value.is_a?(Array)
    value.to_s
  end

  def gender_like_value?(value)
    %w[男 女 male female m f].include?(value.to_s.downcase)
  end

end
