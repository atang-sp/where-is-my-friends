# frozen_string_literal: true

desc "Create a global announcement post and optional category pinned post for Local Friends"
task "where_is_my_friends:create_announcement" => :environment do
  unless SiteSetting.where_is_my_friends_enabled
    puts "Plugin is disabled. Enable where_is_my_friends_enabled first."
    next
  end

  stats = UserLocation.active_for_discovery
  total_members = stats.count
  city_count = stats.distinct.count(:city_key)
  base_url = Discourse.base_url
  link = "#{base_url}/where-is-my-friends"

  locale = SiteSetting.default_locale&.to_sym || :en

  title = I18n.t("where_is_my_friends.announcement.title", locale: locale)
  body = I18n.t(
    "where_is_my_friends.announcement.body",
    count: total_members,
    city_count: city_count,
    link: link,
    locale: locale
  )

  post = PostCreator.create!(
    Discourse.system_user,
    title: title,
    raw: body,
    archetype: Archetype.default,
    category: SiteSetting.uncategorized_category_id
  )

  topic = post.topic
  topic.update!(pinned_globally: true, pinned_at: Time.current)
  puts "Created global announcement: #{base_url}/t/#{topic.slug}/#{topic.id}"

  target_slug = SiteSetting.where_is_my_friends_target_category_slug.presence
  if target_slug
    category = Category.find_by(slug: target_slug)
    if category
      cat_title = I18n.t("where_is_my_friends.announcement.category_title", locale: locale)
      cat_body = I18n.t(
        "where_is_my_friends.announcement.category_body",
        count: total_members,
        city_count: city_count,
        link: link,
        locale: locale
      )

      cat_post = PostCreator.create!(
        Discourse.system_user,
        title: cat_title,
        raw: cat_body,
        archetype: Archetype.default,
        category: category.id
      )
      cat_topic = cat_post.topic
      cat_topic.update!(
        pinned_at: Time.current,
        pinned_until: 10.years.from_now
      )
      puts "Created category pinned post: #{base_url}/t/#{cat_topic.slug}/#{cat_topic.id}"
    else
      puts "Warning: category '#{target_slug}' not found, skipping category pin."
    end
  else
    puts "No target category configured (where_is_my_friends_target_category_slug), skipping category pin."
  end
end
