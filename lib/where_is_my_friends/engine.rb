# frozen_string_literal: true

module ::WhereIsMyFriends
  class Engine < ::Rails::Engine
    engine_name "where_is_my_friends"
    isolate_namespace WhereIsMyFriends
    config.autoload_paths << File.join(config.root, "lib")
    jobs_dirs = [
      "#{config.root}/app/jobs/scheduled",
      "#{config.root}/app/jobs/regular"
    ]
    config.to_prepare do
      jobs_dirs.each do |jobs_dir|
        Rails.autoloaders.main.eager_load_dir(jobs_dir) if Dir.exist?(jobs_dir)
      end
    end
  end
end
