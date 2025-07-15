# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :id, :username, :name, :avatar_template, :distance, :last_seen_at, 
             :is_virtual, :virtual_address, :location_type, :gender, :age, :bio, 
             :user_fields, :title, :created_at, :location_display_name, :is_online

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

  def age
    # 尝试从用户字段中获取年龄信息
    user_fields_data = object[:user].user_fields || {}
    
    age_value = user_fields_data['年龄'] || 
                user_fields_data['age'] || 
                user_fields_data['Age'] ||
                user_fields_data['生日'] ||
                user_fields_data['birthday']
    
    # 如果用户字段中没有年龄信息，尝试从自定义字段获取
    if age_value.blank?
      age_value = object[:user].custom_fields&.dig('age')
    end
    
    return nil if age_value.blank?
    
    # 如果是生日格式，计算年龄
    if age_value.to_s.match(/\d{4}/)
      begin
        birth_year = age_value.to_s.scan(/\d{4}/).first.to_i
        current_year = Date.current.year
        calculated_age = current_year - birth_year
        return calculated_age if calculated_age > 0 && calculated_age < 150
      rescue
        # 如果计算失败，继续处理原值
      end
    end
    
    # 如果是数字字符串，转换为整数
    if age_value.to_s.match(/^\d+$/)
      age_int = age_value.to_i
      return age_int if age_int > 0 && age_int < 150
    end
    
    # 返回原始值（可能是其他格式的年龄表示）
    age_value.to_s
  end

  def bio
    object[:user].user_profile&.bio_raw
  end

  def user_fields
    # 返回所有用户自定义字段
    fields = {}
    
    # 获取用户字段数据
    if object[:user].user_fields.present?
      object[:user].user_fields.each do |key, value|
        next if value.blank?
        # 排除已经单独处理的字段
        next if ['性别', 'gender', 'Gender', 'sex', 'Sex', '年龄', 'age', 'Age', '生日', 'birthday'].include?(key)
        fields[key] = value
      end
    end
    
    # 获取自定义字段
    if object[:user].custom_fields.present?
      object[:user].custom_fields.each do |key, value|
        next if value.blank?
        next if ['gender', 'age'].include?(key)
        fields[key] = value
      end
    end
    
    fields
  end

  def title
    object[:user].title
  end

  def created_at
    object[:user].created_at
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