# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class StackExchangeClient
      class SourceError < ::WhereIsMyFriends::LicensedImport::SourceError
      end
      class MissingSource < ::WhereIsMyFriends::LicensedImport::MissingSource
      end

      API_ROOT = "https://api.stackexchange.com/2.3"
      SITE = "interpersonal"
      PAGE_SIZE = 100
      MAX_QUESTION_PAGES = 10
      MAX_ANSWER_PAGES = 20
      SOURCE_TYPE = "stack_exchange"

      def initialize(open_timeout: 5, read_timeout: 15)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def candidates
        documents = []
        1.upto(MAX_QUESTION_PAGES) do |page|
          response =
            get_json(
              "/questions",
              page: page,
              pagesize: PAGE_SIZE,
              order: "desc",
              sort: "votes",
              site: SITE,
              filter: "withbody"
            )
          questions = response.fetch("items", [])
          break if questions.empty?

          answers =
            answers_for(
              questions.map { |question| question.fetch("question_id") }
            )
          documents.concat(
            questions.filter_map do |question|
              build_document(
                question,
                answers: answers.fetch(question.fetch("question_id"), [])
              )
            end
          )
          break unless response["has_more"]
        end
        documents
      end

      def source_type
        SOURCE_TYPE
      end

      def fetch(question_id)
        response =
          get_json(
            "/questions/#{Integer(question_id)}",
            site: SITE,
            filter: "withbody"
          )
        question = response.fetch("items", []).first
        raise MissingSource if question.blank?

        answers = answers_for([question.fetch("question_id")])
        build_document(
          question,
          answers: answers.fetch(question.fetch("question_id"), [])
        ) || raise(MissingSource)
      end

      private

      def build_document(question, answers:)
        question_id = question.fetch("question_id")
        return if answers.empty?

        accepted_id = question["accepted_answer_id"]
        answer = answers.find { |entry| entry["answer_id"] == accepted_id }
        answer ||= answers.max_by { |entry| entry.fetch("score", 0) }
        revision_epoch = [
          question["last_edit_date"] || question["creation_date"],
          answer["last_edit_date"] || answer["creation_date"]
        ].compact.max

        {
          source_type: SOURCE_TYPE,
          question_id: question_id,
          answer_id: answer.fetch("answer_id"),
          question_url: question.fetch("link"),
          answer_url:
            answer["link"] ||
              "https://interpersonal.stackexchange.com/a/#{answer.fetch("answer_id")}",
          question_author: owner_name(question),
          answer_author: owner_name(answer),
          question_license: question["content_license"],
          answer_license: answer["content_license"],
          title: CGI.unescapeHTML(question.fetch("title").to_s),
          question_html: question.fetch("body").to_s,
          answer_html: answer.fetch("body").to_s,
          revised_at: revision_epoch && Time.zone.at(revision_epoch)
        }
      end

      def answers_for(question_ids)
        grouped = Hash.new { |hash, question_id| hash[question_id] = [] }
        path = "/questions/#{question_ids.join(";")}/answers"
        1.upto(MAX_ANSWER_PAGES) do |page|
          response =
            get_json(
              path,
              page: page,
              pagesize: PAGE_SIZE,
              order: "desc",
              sort: "votes",
              site: SITE,
              filter: "withbody"
            )
          response
            .fetch("items", [])
            .each do |answer|
              question_id = answer["question_id"]
              question_id ||= question_ids.first if question_ids.one?
              if question_ids.include?(question_id)
                grouped[question_id] << answer
              end
            end
          break unless response["has_more"]
        end
        grouped
      end

      def owner_name(post)
        deleted_user =
          I18n.t(
            "where_is_my_friends.licensed_import.deleted_source_user",
            locale: :zh_CN
          )
        CGI.unescapeHTML(
          post.dig("owner", "display_name").presence || deleted_user
        )
      end

      def get_json(path, params)
        uri = URI("#{API_ROOT}#{path}")
        uri.query = URI.encode_www_form(params)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = "where-is-my-friends/#{plugin_version}"
        response =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true,
            open_timeout: @open_timeout,
            read_timeout: @read_timeout
          ) { |http| http.request(request) }
        raise SourceError unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        raise SourceError if payload["error_id"] || payload["backoff"]

        payload
      rescue JSON::ParserError,
             Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError
        raise SourceError
      end

      def plugin_version
        Discourse.plugins_by_name["where-is-my-friends"]&.metadata&.version ||
          "unknown"
      end
    end
  end
end
