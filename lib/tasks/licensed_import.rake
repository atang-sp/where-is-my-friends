# frozen_string_literal: true

namespace :where_is_my_friends do
  namespace :licensed_import do
    desc "Stop licensed imports and hide topics for a confirmed incident"
    task :halt,
         %i[source_type source_question_id reason] =>
           :environment do |_task, args|
      source_type = args.fetch(:source_type)
      source_question_id = Integer(args.fetch(:source_question_id))
      reason = args.fetch(:reason)
      WhereIsMyFriends::LicensedImport::IncidentResponder.new.halt!(
        source_type: source_type,
        source_question_id: source_question_id,
        reason: reason
      )
      puts "Licensed import halted for #{source_type}:#{source_question_id}: #{reason}"
    end

    desc "Publish one fully validated licensed import preview"
    task :publish_preview, [:record_id] => :environment do |_task, args|
      record_id = Integer(args.fetch(:record_id))
      post =
        WhereIsMyFriends::LicensedImport::PreviewPublisher.new.call(record_id)
      puts "Licensed import preview #{record_id} published as topic #{post.topic_id}"
    end
  end
end
