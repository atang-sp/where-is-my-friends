# frozen_string_literal: true

class SeedExpandedInterestCatalogue < ActiveRecord::Migration[8.0]
  def up
    return unless Migration::Helpers.existing_site?

    execute <<~SQL
      INSERT INTO tags (name, created_at, updated_at)
      VALUES
        ('恋痛型', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('管教型', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('场景代入型', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('疼爱型', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('好奇探索型', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('师生场景', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('家庭管教', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('朋友闺蜜', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('古风宫廷', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('职场上下级', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('军训教官', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('OTK膝上', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('趴在桌床上', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('站立弯腰', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('跪姿', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('皮带', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('皮拍', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('发刷', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('木勺', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('教鞭', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('竹条', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('鸡毛掸子', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('拥抱安慰', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('查看上药', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('事后聊天', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('独处冷静', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('定期实践', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('偶尔实践', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
        ('仅限线上', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (name) DO NOTHING
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
