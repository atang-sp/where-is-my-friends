# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class PostFormatter
      LICENSE_URLS = {
        "CC BY-SA 3.0" => "https://creativecommons.org/licenses/by-sa/3.0/",
        "CC BY-SA 4.0" => "https://creativecommons.org/licenses/by-sa/4.0/"
      }.freeze
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
          translate("modifications.translated"),
          *content.redactions.map { |reason| redaction_label(reason) }
        ].uniq.join(translate("modifications.separator"))

        {
          title:
            "#{translate("title_prefix")} #{translation.fetch("translated_title").strip}",
          raw: <<~MARKDOWN.strip
            > #{translate("post.disclosure")}

            ## #{translate("post.question_heading")}

            #{question}

            ## #{translate("post.answer_heading")}

            #{answer}

            ---

            ## #{translate("post.discussion_heading")}

            #{translation.fetch("discussion_prompt").strip}

            ---

            ### #{translate("post.attribution_heading")}

            #{translate("post.question_attribution", author: author_link(document.fetch(:question_author), document.fetch(:question_url)), url: document.fetch(:question_url), license: license_link(document.fetch(:question_license)))}
            #{translate("post.answer_attribution", author: author_link(document.fetch(:answer_author), document.fetch(:answer_url)), url: document.fetch(:answer_url), license: license_link(document.fetch(:answer_license)))}
            #{translate("post.modification_notice", modification: modification)}
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
        translate("redactions.#{reason}")
      end

      def translate(key, **options)
        I18n.t(
          "where_is_my_friends.licensed_import.#{key}",
          locale: :zh_CN,
          **options
        )
      end
    end
  end
end
