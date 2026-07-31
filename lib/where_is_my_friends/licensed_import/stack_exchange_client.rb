# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class StackExchangeClient
      class SourceError < StandardError
      end
      class MissingSource < SourceError
      end

      API_ROOT = "https://api.stackexchange.com/2.3"
      SITE = "interpersonal"
      PAGE_SIZE = 30

      def initialize(open_timeout: 5, read_timeout: 15)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def candidates
        response =
          get_json(
            "/questions",
            pagesize: PAGE_SIZE,
            order: "desc",
            sort: "votes",
            site: SITE,
            filter: "withbody"
          )
        response
          .fetch("items", [])
          .filter_map { |question| build_document(question) }
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

        build_document(question) || raise(MissingSource)
      end

      private

      def build_document(question)
        question_id = question.fetch("question_id")
        answers =
          get_json(
            "/questions/#{question_id}/answers",
            pagesize: 100,
            order: "desc",
            sort: "votes",
            site: SITE,
            filter: "withbody"
          ).fetch("items", [])
        return if answers.empty?

        accepted_id = question["accepted_answer_id"]
        answer = answers.find { |entry| entry["answer_id"] == accepted_id }
        answer ||= answers.max_by { |entry| entry.fetch("score", 0) }
        revision_epoch = [
          question["last_edit_date"] || question["creation_date"],
          answer["last_edit_date"] || answer["creation_date"]
        ].compact.max

        {
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

      def owner_name(post)
        CGI.unescapeHTML(post.dig("owner", "display_name").presence || "已删除用户")
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
