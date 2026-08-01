# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class WikimediaClient
      class SourceError < ::WhereIsMyFriends::LicensedImport::SourceError
      end
      class MissingSource < ::WhereIsMyFriends::LicensedImport::MissingSource
      end

      API_URL = "https://en.wikipedia.org/w/api.php"
      SOURCE_TYPE = "wikimedia"
      LICENSE = "CC BY-SA 4.0"
      LICENSE_URL_PREFIX = "https://creativecommons.org/licenses/by-sa/4.0/"
      CONTRIBUTOR_NAME = "Wikipedia contributors"
      LEAD_SECTION = "__lead__"
      REMOVED_SELECTORS = %w[
        style
        script
        table
        figure
        img
        sup.reference
        .mw-editsection
        .metadata
        .navbox
        .hatnote
      ].freeze
      PAGES = [
        {
          page_id: 1_008_761,
          title: "Aftercare (BDSM)",
          sections: ["Overview", "Relational benefits"],
          theme_hint: "aftercare"
        },
        {
          page_id: 44_439,
          title: "Erotic spanking",
          sections: ["Implements", "Safety", "Psychology and prevalence"],
          theme_hint: "spanking"
        },
        {
          page_id: 638_323,
          title: "Discipline (BDSM)",
          sections: %w[__lead__ Punishment],
          theme_hint: "discipline"
        }
      ].freeze

      def initialize(pages: PAGES, open_timeout: 5, read_timeout: 15)
        @pages = pages
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def source_type
        SOURCE_TYPE
      end

      def candidates
        verify_license!
        documents = []
        failures = 0
        @pages.each do |page|
          documents << build_document(page)
        rescue ::WhereIsMyFriends::LicensedImport::SourceError
          failures += 1
        end
        raise SourceError if documents.empty? && failures.positive?

        documents
      end

      def fetch(page_id)
        verify_license!
        page = @pages.find { |candidate| candidate.fetch(:page_id) == page_id }
        raise MissingSource if page.blank?

        build_document(page)
      end

      private

      def build_document(page)
        metadata =
          parse(
            page: page.fetch(:title),
            prop: "text|sections|revid|displaytitle"
          )
        unless metadata.fetch("pageid") == page.fetch(:page_id)
          raise MissingSource
        end

        section_anchors =
          anchors_for(metadata.fetch("sections"), page.fetch(:sections))
        revision_id = metadata.fetch("revid")
        blocks = section_blocks(metadata.fetch("text"), section_anchors)
        question_html, answer_html = split_blocks(blocks)
        title = plain_text(metadata.fetch("displaytitle"))

        {
          source_type: SOURCE_TYPE,
          content_kind: "article",
          adult_confirmed: true,
          theme_hint: page.fetch(:theme_hint),
          question_id: page.fetch(:page_id),
          answer_id: revision_id,
          question_url: article_url(page.fetch(:title)),
          answer_url: revision_url(page.fetch(:title), revision_id),
          question_author: CONTRIBUTOR_NAME,
          answer_author: CONTRIBUTOR_NAME,
          question_license: LICENSE,
          answer_license: LICENSE,
          title: title,
          question_html: question_html,
          answer_html: answer_html,
          revised_at: nil
        }
      rescue KeyError, ArgumentError, JSON::ParserError
        raise SourceError
      end

      def anchors_for(sections, required_names)
        index_by_name =
          sections.index_by do |section|
            plain_text(section.fetch("line")).downcase
          end
        required_names.map do |name|
          next { anchor: LEAD_SECTION, level: 6 } if name == LEAD_SECTION

          section = index_by_name.fetch(name.downcase)
          {
            anchor: section.fetch("anchor"),
            level: Integer(section.fetch("level"))
          }
        end
      rescue KeyError
        raise MissingSource
      end

      def section_blocks(html, anchors)
        fragment = Nokogiri::HTML5.fragment(html)
        REMOVED_SELECTORS.each { |selector| fragment.css(selector).remove }
        fragment.css("a").each { |link| link.replace(link.children) }
        root = fragment.at_css(".mw-parser-output") || fragment
        nodes =
          root
            .children
            .select(&:element?)
            .reject { |node| node.text.squish.blank? }

        anchors.flat_map do |selection|
          anchor = selection.fetch(:anchor)
          start_index =
            if anchor == LEAD_SECTION
              0
            else
              nodes.index { |node| heading(node)&.fetch(:anchor) == anchor }
            end
          raise MissingSource if start_index.blank?

          selected = []
          nodes
            .drop(start_index)
            .each_with_index do |node, offset|
              current_heading = heading(node)
              if offset.positive? && current_heading.present? &&
                   current_heading.fetch(:level) <= selection.fetch(:level)
                break
              end

              selected << node.to_html
            end
          selected
        end
      end

      def heading(node)
        element = node.css("h2, h3, h4, h5, h6").first
        return if element.blank?

        { anchor: element["id"], level: element.name.delete_prefix("h").to_i }
      end

      def split_blocks(blocks)
        raise MissingSource if blocks.length < 2

        midpoint = (blocks.length / 2.0).ceil
        [blocks.first(midpoint).join("\n"), blocks.drop(midpoint).join("\n")]
      end

      def parse(**params)
        payload =
          get_json(
            { action: "parse", format: "json", formatversion: 2 }.merge(params)
          )
        raise SourceError if payload["error"]

        payload.fetch("parse")
      end

      def verify_license!
        payload =
          get_json(
            action: "query",
            format: "json",
            formatversion: 2,
            meta: "siteinfo",
            siprop: "rightsinfo"
          )
        rights = payload.dig("query", "rightsinfo")
        raise SourceError unless rights.is_a?(Hash)
        unless rights["url"].to_s.start_with?(LICENSE_URL_PREFIX) &&
                 rights["text"].to_s.match?(
                   /Attribution[- ]Share ?Alike(?: License)? 4\.0/i
                 )
          raise SourceError
        end
      end

      def get_json(params)
        uri = URI(API_URL)
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

        JSON.parse(response.body)
      rescue Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError
        raise SourceError
      end

      def article_url(title)
        "https://en.wikipedia.org/wiki/#{URI::DEFAULT_PARSER.escape(title.tr(" ", "_"))}"
      end

      def revision_url(title, revision_id)
        encoded_title = CGI.escape(title.tr(" ", "_"))
        "https://en.wikipedia.org/w/index.php?title=#{encoded_title}&oldid=#{revision_id}"
      end

      def plain_text(html)
        Nokogiri::HTML5.fragment(html.to_s).text.squish
      end

      def plugin_version
        Discourse.plugins_by_name["where-is-my-friends"]&.metadata&.version ||
          "unknown"
      end
    end
  end
end
