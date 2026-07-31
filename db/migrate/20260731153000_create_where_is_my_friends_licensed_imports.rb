# frozen_string_literal: true

class CreateWhereIsMyFriendsLicensedImports < ActiveRecord::Migration[7.0]
  def change
    create_table :where_is_my_friends_licensed_imports do |t|
      t.bigint :source_question_id, null: false
      t.bigint :source_answer_id
      t.string :source_question_url
      t.string :source_answer_url
      t.string :question_author
      t.string :answer_author
      t.string :question_license
      t.string :answer_license
      t.datetime :source_revised_at
      t.string :theme
      t.string :status, null: false
      t.string :failure_code
      t.integer :token_count, null: false, default: 0
      t.bigint :topic_id
      t.bigint :first_post_id
      t.string :translated_title
      t.text :translated_body
      t.datetime :published_at
      t.timestamps
    end

    add_index :where_is_my_friends_licensed_imports,
              %i[source_question_id created_at],
              name: "idx_wimf_licensed_import_source"
    add_index :where_is_my_friends_licensed_imports,
              %i[status created_at],
              name: "idx_wimf_licensed_import_status"
    add_index :where_is_my_friends_licensed_imports,
              :topic_id,
              name: "idx_wimf_licensed_import_topic"
  end
end
