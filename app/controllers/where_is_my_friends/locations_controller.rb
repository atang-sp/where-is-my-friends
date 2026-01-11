# frozen_string_literal: true
require 'net/http'
require 'uri'

module WhereIsMyFriends
  class LocationsController < ::ApplicationController
    requires_plugin 'where-is-my-friends'
    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    def index
      # Return initial data for the frontend
      current_user_location = UserLocation.find_by(user_id: current_user.id, enabled: true)
      
      response_data = {
        currentUser: {
          id: current_user.id,
          username: current_user.username,
          location: current_user_location ? {
            latitude: current_user_location.latitude,
            longitude: current_user_location.longitude,
            is_virtual: current_user_location.is_virtual || false,
            virtual_address: current_user_location.virtual_address,
            location_type: current_user_location.location_type || 'real'
          } : nil
        },
        users: [], # Will be populated when user shares location
        settings: {
          virtual_location_enabled: SiteSetting.where_is_my_friends_enable_virtual_location,
          map_provider: SiteSetting.where_is_my_friends_map_provider,
          has_amap_key: SiteSetting.where_is_my_friends_amap_api_key.present?,
          has_baidu_key: SiteSetting.where_is_my_friends_baidu_api_key.present?,
          max_users_display: (SiteSetting.where_is_my_friends_max_users_display rescue 50)
        }
      }
      
      render json: response_data
    end

    def create
      # Update user's location
      latitude = params[:latitude].to_f
      longitude = params[:longitude].to_f
      
      # 更强健的布尔值转换
      is_virtual = ActiveModel::Type::Boolean.new.cast(params[:is_virtual])
      virtual_address = params[:virtual_address].to_s.strip if params[:virtual_address].present?
      
      # 获取定位来源和精度信息
      location_source = params[:location_source].to_s.presence || 'unknown'
      location_accuracy = params[:location_accuracy].to_f if params[:location_accuracy].present?

      # 详细日志：记录收到的原始数据
      Rails.logger.info "WhereIsMyFriends: [CREATE] User=#{current_user.username} " \
                        "lat=#{latitude} lng=#{longitude} " \
                        "source=#{location_source} accuracy=#{location_accuracy || 'N/A'} " \
                        "is_virtual=#{is_virtual}"

      # 验证坐标
      if latitude.abs > 90 || longitude.abs > 180
        Rails.logger.warn "WhereIsMyFriends: [REJECT] Invalid coordinates for user #{current_user.username}"
        return render_json_error(I18n.t('where_is_my_friends.invalid_coordinates'), status: 422)
      end

      # 验证坐标不能为零（通常表示定位失败）
      if latitude == 0.0 && longitude == 0.0
        Rails.logger.warn "WhereIsMyFriends: [REJECT] Zero coordinates for user #{current_user.username}"
        return render_json_error("无效的坐标数据", status: 422)
      end
      
      # 检查 IP 定位精度：如果来源是 IP 且精度过低，警告用户
      if location_source == 'ip' && !is_virtual
        Rails.logger.warn "WhereIsMyFriends: [LOW_ACCURACY] User #{current_user.username} using IP-based location"
      end

      # Check if virtual location is enabled
      if is_virtual && !SiteSetting.where_is_my_friends_enable_virtual_location
        return render_json_error("虚拟定位功能未启用", status: 422)
      end

      # 虚拟位置必须提供地址信息
      if is_virtual && virtual_address.blank?
        return render_json_error("虚拟位置必须提供地址信息", status: 422)
      end

      begin
        location = UserLocation.upsert_location(current_user.id, latitude, longitude, {
          is_virtual: is_virtual,
          virtual_address: virtual_address,
          location_source: location_source,
          location_accuracy: location_accuracy
        })
        
        if location.persisted?
          location_type = is_virtual ? "虚拟位置" : "真实位置"
          Rails.logger.info "WhereIsMyFriends: User #{current_user.username} updated #{location_type} to (#{latitude}, #{longitude})"
          
          render json: success_json.merge({
            location: {
              latitude: location.latitude,
              longitude: location.longitude,
              is_virtual: location.is_virtual,
              virtual_address: location.virtual_address,
              location_type: location.location_type
            }
          })
        else
          Rails.logger.error "WhereIsMyFriends: Failed to save location for user #{current_user.username}: #{location.errors.full_messages.join(', ')}"
          render_json_error("保存位置失败: #{location.errors.full_messages.join(', ')}", status: 422)
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "WhereIsMyFriends: Validation error for user #{current_user.username}: #{e.message}"
        render_json_error("数据验证失败: #{e.message}", status: 422)
      rescue => e
        Rails.logger.error "WhereIsMyFriends: Error updating location for user #{current_user.username}: #{e.message}\n#{e.backtrace.join("\n")}"
        render_json_error("系统错误: #{e.message}", status: 500)
      end
    end

    def nearby
      # Get nearby users
      latitude = params[:latitude].to_f
      longitude = params[:longitude].to_f
      # Determine search distance based on site settings
      requested_distance = params[:distance].present? ? params[:distance].to_f : SiteSetting.where_is_my_friends_default_distance_km
      max_distance = SiteSetting.where_is_my_friends_max_distance_km
      distance = [requested_distance, max_distance].min

      Rails.logger.info "WhereIsMyFriends: [NEARBY] Searching near (#{latitude}, #{longitude}) within #{distance}km"

      if latitude.abs > 90 || longitude.abs > 180
        Rails.logger.error "WhereIsMyFriends: [NEARBY] Invalid coordinates (#{latitude}, #{longitude})"
        return render_json_error(I18n.t('where_is_my_friends.invalid_coordinates'))
      end

      begin
        # 查找所有启用的位置，包括当前用户
        # 使用站点设置中配置的最大显示数量，如果设置不存在则使用默认值50
        max_users_display = SiteSetting.where_is_my_friends_max_users_display rescue 50
        nearby_users = UserLocation.nearby(latitude, longitude, distance)
          .where(enabled: true)
          .includes(:user => [:user_profile])
          .limit(max_users_display)

        # 统计定位来源分布
        source_stats = nearby_users.group(:location_source).count
        Rails.logger.info "WhereIsMyFriends: [NEARBY] Found #{nearby_users.count} users - sources: #{source_stats}"
        
        # 检查是否有大量低精度定位
        ip_count = source_stats['ip'] || 0
        gps_count = source_stats['gps'] || 0
        unknown_count = source_stats['unknown'] || 0
        total_real = ip_count + gps_count + unknown_count
        
        if total_real > 0 && (ip_count + unknown_count) > gps_count
          Rails.logger.warn "WhereIsMyFriends: [NEARBY] Warning - majority of users using low-accuracy location " \
                            "(IP: #{ip_count}, GPS: #{gps_count}, Unknown: #{unknown_count})"
        end

        # Calculate distances and include current user
        users_with_distance = nearby_users.map do |location|
          distance_km = location.distance_to(latitude, longitude)
          
          # 对于低精度定位，距离可能不准确，记录警告
          if location.low_accuracy? && distance_km < 1.0
            Rails.logger.debug "WhereIsMyFriends: [NEARBY] User #{location.user.username} shows #{distance_km.round(1)}km " \
                              "but using low-accuracy location (source: #{location.location_source})"
          end
          
          {
            user: location.user,
            distance: distance_km.round(1),
            location: location,
            isCurrentUser: location.user_id == current_user.id
          }
        end.sort_by { |u| u[:distance] }

        # 确保当前用户也在结果中（如果他们有位置）
        current_user_location = UserLocation.find_by(user_id: current_user.id, enabled: true)
        if current_user_location && !users_with_distance.any? { |u| u[:isCurrentUser] }
          current_distance = current_user_location.distance_to(latitude, longitude)
          if current_distance <= distance
            users_with_distance.unshift({
              user: current_user,
              distance: current_distance.round(1),
              location: current_user_location,
              isCurrentUser: true
            })
          end
        end

        Rails.logger.info "WhereIsMyFriends: [NEARBY] Returning #{users_with_distance.count} users"
        
        # 计算统计信息
        low_accuracy_count = users_with_distance.count { |u| u[:location].low_accuracy? }
        very_close_count = users_with_distance.count { |u| u[:distance] < 1.0 }
        
        # 如果大量用户距离都小于1km且多数是低精度定位，发出警告
        warning = nil
        if very_close_count > 3 && low_accuracy_count > very_close_count / 2
          warning = "检测到多个用户距离显示很近，但其中多数使用IP定位（精度较低）。实际距离可能有数公里误差。"
          Rails.logger.warn "WhereIsMyFriends: [NEARBY] #{warning}"
        end

        render json: {
          users: users_with_distance.map { |u| UserLocationSerializer.new(u, root: false) },
          total: users_with_distance.count,
          searchLocation: { latitude: latitude, longitude: longitude },
          searchDistance: distance,
          stats: {
            low_accuracy_count: low_accuracy_count,
            very_close_count: very_close_count,
            gps_count: gps_count,
            ip_count: ip_count
          },
          warning: warning
        }
      rescue => e
        Rails.logger.error "WhereIsMyFriends: Error finding nearby users: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render_json_error("查找附近用户时发生错误: #{e.message}")
      end
    end

    def ip_location
      # 获取客户端真实 IP（而不是服务器 IP）
      client_ip = request.remote_ip
      uri = URI("http://ip-api.com/json/#{client_ip}")

      begin
        response = Net::HTTP.get_response(uri)
        render json: response.body
      rescue => e
        Rails.logger.error "WhereIsMyFriends: IP location request failed - #{e.message}"
        render_json_error("IP 定位请求失败: #{e.message}")
      end
    end

    def destroy
      # Remove user's location
      location = UserLocation.find_by(user_id: current_user.id)
      location&.update(enabled: false)
      render json: success_json
    end
    
    # 调试端点：分析当前位置数据分布
    def debug_stats
      # 仅管理员可访问
      raise Discourse::InvalidAccess unless current_user.admin?
      
      total_locations = UserLocation.enabled.count
      real_locations = UserLocation.enabled.real_locations.count
      virtual_locations = UserLocation.enabled.virtual_locations.count
      
      # 统计定位来源分布
      source_stats = UserLocation.enabled.group(:location_source).count
      
      # 统计坐标聚集情况（四舍五入到小数点后2位，约1km精度）
      coordinate_clusters = UserLocation.enabled
        .select("ROUND(latitude, 2) as lat_cluster, ROUND(longitude, 2) as lng_cluster, COUNT(*) as count")
        .group("lat_cluster, lng_cluster")
        .having("COUNT(*) > 1")
        .order("count DESC")
        .limit(20)
        .map { |c| { lat: c.lat_cluster, lng: c.lng_cluster, count: c.count } }
      
      # 低精度定位统计
      low_accuracy_count = UserLocation.enabled.where(location_source: 'ip').count
      gps_count = UserLocation.enabled.where(location_source: 'gps').count
      unknown_source = UserLocation.enabled.where(location_source: [nil, 'unknown', '']).count
      
      render json: {
        total: total_locations,
        real: real_locations,
        virtual: virtual_locations,
        by_source: source_stats,
        low_accuracy_ip: low_accuracy_count,
        gps_precise: gps_count,
        unknown_source: unknown_source,
        coordinate_clusters: coordinate_clusters,
        warning: coordinate_clusters.any? ? "检测到坐标聚集！可能存在定位问题。" : nil
      }
    end

    private

    def ensure_plugin_enabled
      unless SiteSetting.where_is_my_friends_enabled
        raise Discourse::NotFound
      end
    end

  end
end 