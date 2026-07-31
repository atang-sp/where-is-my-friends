# frozen_string_literal: true

namespace :where_is_my_friends do
  namespace :licensed_import do
    desc "Stop licensed imports and hide topics for a confirmed incident"
    task :halt, %i[source_question_id reason] => :environment do |_task, args|
      source_question_id = Integer(args.fetch(:source_question_id))
      reason = args.fetch(:reason)
      WhereIsMyFriends::LicensedImport::IncidentResponder.new.halt!(
        source_question_id: source_question_id,
        reason: reason
      )
      puts "Licensed import halted for source question #{source_question_id}: #{reason}"
    end
  end
end
