# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class PostFormatter
      LICENSE_URLS = {
        "CC BY-SA 3.0" => "https://creativecommons.org/licenses/by-sa/3.0/",
        "CC BY-SA 4.0" => "https://creativecommons.org/licenses/by-sa/4.0/"
      }.freeze
      TITLE_PREFIX = "[英文精选·译文]"

      def call(document:, content:, translation:)
        translated =
          translation.fetch("segments").index_by { |entry| entry.fetch("id") }
        question =
          content
            .segments
            .select { |segment| segment.kind == "question" }
            .map { |segment| translated.fetch(segment.id).fetch("translation") }
            .join("\n\n")
        answer =
          content
            .segments
            .select { |segment| segment.kind == "answer" }
            .map { |segment| translated.fetch(segment.id).fetch("translation") }
            .join("\n\n")
        modification = [
          "翻译为简体中文",
          *content.redactions.map { |reason| redaction_label(reason) }
        ].uniq.join("；")

        {
          title:
            "#{TITLE_PREFIX} #{translation.fetch("translated_title").strip}",
          raw: <<~MARKDOWN.strip
            > 本主题由英文精选翻译机器人自动生成，并经过许可、安全与忠实度校验。下文是中文译文；“社区讨论”不是原作者内容。

            ## 问题

            #{question}

            ## 优质回答

            #{answer}

            ---

            ## 社区讨论

            #{translation.fetch("discussion_prompt").strip}

            ---

            ### 来源、署名与许可

            - 问题：#{author_link(document.fetch(:question_author), document.fetch(:question_url))} · [原文](#{document.fetch(:question_url)}) · #{license_link(document.fetch(:question_license))}
            - 回答：#{author_link(document.fetch(:answer_author), document.fetch(:answer_url))} · [原文](#{document.fetch(:answer_url)}) · #{license_link(document.fetch(:answer_license))}
            - 修改说明：#{modification}。未改变的部分按相同许可转载。
          MARKDOWN
        }
      end

      private

      def author_link(name, url)
        "[#{escape_label(name)}](#{url})"
      end

      def license_link(license)
        "[#{escape_label(license)}](#{LICENSE_URLS.fetch(license)})"
      end

      def escape_label(value)
        value.to_s.gsub(/([\[\]\\])/, '\\\\\1')
      end

      def redaction_label(reason)
        {
          "contact_information" => "删除联系方式",
          "exact_address" => "删除精确地址",
          "image" => "删除图片",
          "long_quote" => "删除无独立许可的长引用"
        }.fetch(reason)
      end
    end
  end
end
