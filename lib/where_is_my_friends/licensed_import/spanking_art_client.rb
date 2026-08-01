# frozen_string_literal: true

require "net/http"
require "zlib"

module WhereIsMyFriends
  module LicensedImport
    class SpankingArtClient
      class SourceError < ::WhereIsMyFriends::LicensedImport::SourceError
      end
      class MissingSource < ::WhereIsMyFriends::LicensedImport::MissingSource
      end

      SOURCE_TYPE = "spanking_art"
      LICENSE = "GFDL 1.3"
      CONTRIBUTOR_NAME = "Spanking Art Wiki contributors"
      LEAD_SECTION = "__lead__"
      ARCHIVE_ORIGIN = "https://web.archive.org"
      SOURCE_ORIGIN = "https://spankingart.org"
      REMOVED_SELECTORS = %w[
        style
        script
        table
        figure
        img
        picture
        video
        audio
        sup.reference
        .mw-editsection
        .metadata
        .navbox
        .hatnote
        .toc
        .thumb
        .gallery
        .magnify
        .mw-empty-elt
      ].freeze
      DEFAULT_EXCLUDED_PATTERNS = [
        /\b(?:child|children|underage|minor|puberty)\b/i,
        /\b(?:boy|girl) spanking\b/i,
        %r{\b(?:ageplay|parent/child|teacher/student|schoolgirl)\b}i,
        /\bnon-?consent(?:sual(?:ity)?)?\b/i,
        /\b(?:pornographic|explicit sex)\b/i
      ].freeze
      PAGES = [
        {
          page_id: 1_232,
          revision_id: 152_283,
          slug: "Safeword",
          title: "Safeword",
          snapshot_at: "20250101070711",
          sections: [
            LEAD_SECTION,
            "Why safewords?",
            "Slowwords and safewords",
            "Nonverbal safewords",
            "Safewords in parties and clubs"
          ],
          theme_hint: "boundaries"
        },
        {
          page_id: 1_120,
          revision_id: 145_642,
          slug: "Spanko",
          title: "Spanko",
          snapshot_at: "20250112095407",
          sections: [
            LEAD_SECTION,
            "General",
            "Creative spankos",
            "From individuals to subculture"
          ],
          theme_hint: "making_friends"
        },
        {
          page_id: 1_909,
          revision_id: 113_528,
          slug: "Janus",
          title: "Janus",
          snapshot_at: "20220120015808",
          sections: [LEAD_SECTION, "History"],
          theme_hint: "spanking"
        },
        {
          page_id: 1_031,
          revision_id: 167_986,
          slug: "BDSM",
          title: "BDSM",
          snapshot_at: "20250502063258",
          sections: [
            LEAD_SECTION,
            "Terminology",
            "Symbols",
            "The BDSM and the spanking subculture"
          ],
          minimum_word_count: 390,
          theme_hint: "communication"
        },
        {
          page_id: 1_109,
          revision_id: 119_686,
          slug: "Spanking_clubs",
          title: "Spanking clubs",
          snapshot_at: "20230601183951",
          sections: [
            LEAD_SECTION,
            "Australia",
            "Belgium",
            "Denmark/Scandinavia",
            "France",
            "Germany",
            "Netherlands",
            "U.K.",
            "U.S.A."
          ],
          theme_hint: "making_friends"
        }
      ].freeze

      def initialize(
        pages: PAGES,
        open_timeout: 5,
        read_timeout: 20,
        excluded_patterns: DEFAULT_EXCLUDED_PATTERNS
      )
        @pages = pages
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @excluded_patterns = excluded_patterns
      end

      def source_type
        SOURCE_TYPE
      end

      def candidates
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
        page = @pages.find { |candidate| candidate.fetch(:page_id) == page_id }
        raise MissingSource if page.blank?

        build_document(page)
      end

      private

      def build_document(page)
        url = snapshot_url(page)
        html = get_html(url)
        document = Nokogiri.HTML5(html)
        verify_identity!(document, page)
        verify_license!(document)

        blocks = section_blocks(document, page.fetch(:sections))
        question_html, answer_html = split_blocks(blocks)

        {
          source_type: SOURCE_TYPE,
          content_kind: "article",
          adult_confirmed: true,
          theme_hint: page.fetch(:theme_hint),
          question_id: page.fetch(:page_id),
          answer_id: page.fetch(:revision_id),
          question_url: source_url(page),
          answer_url: url,
          question_author: CONTRIBUTOR_NAME,
          answer_author: CONTRIBUTOR_NAME,
          question_license: LICENSE,
          answer_license: LICENSE,
          title: page.fetch(:title),
          source_title: page.fetch(:title),
          source_history_url: history_url(page),
          source_revision_url: revision_url(page),
          source_snapshot_at: page.fetch(:snapshot_at),
          minimum_word_count: page.fetch(:minimum_word_count, 400),
          question_html: question_html,
          answer_html: answer_html,
          revised_at: nil
        }
      rescue KeyError, ArgumentError
        raise SourceError
      end

      def get_html(url)
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "text/html"
        request["Accept-Encoding"] = "gzip"
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

        decode_body(response.body)
      rescue Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError,
             Zlib::Error
        raise SourceError
      end

      def decode_body(body)
        return body unless body.to_s.b.start_with?("\x1F\x8B".b)

        Zlib::GzipReader.new(StringIO.new(body)).read
      end

      def verify_identity!(document, page)
        html = document.to_html
        article_id = html[/["']wgArticleId["']\s*:\s*(\d+)/, 1]
        revision_id = html[/["']wgCurRevisionId["']\s*:\s*(\d+)/, 1]
        unless article_id.to_i == page.fetch(:page_id) &&
                 revision_id.to_i == page.fetch(:revision_id)
          raise MissingSource
        end
      end

      def verify_license!(document)
        notice = document.at_css("#footer-info-copyright, #copyright")
        unless notice&.text.to_s.squish.match?(
                 /Content is available under GFDL unless otherwise noted\./i
               ) && notice.at_css("a")&.text.to_s.squish.casecmp?("GFDL")
          raise SourceError
        end
      end

      def section_blocks(document, required_names)
        root = document.at_css(".mw-parser-output")
        raise MissingSource if root.blank?

        REMOVED_SELECTORS.each { |selector| root.css(selector).remove }
        root.css("a").each { |link| link.replace(link.children) }
        nodes =
          root
            .children
            .select(&:element?)
            .reject { |node| node.text.squish.blank? }

        required_names.flat_map do |name|
          start_index, level = section_start(nodes, name)
          selected = []
          nodes
            .drop(start_index)
            .each_with_index do |node, offset|
              current = heading(node)
              if offset.positive? && current.present? &&
                   current.fetch(:level) <= level
                break
              end
              next if excluded?(node.text)

              selected << node.to_html
            end
          selected
        end
      end

      def section_start(nodes, name)
        return 0, 6 if name == LEAD_SECTION

        index =
          nodes.index do |node|
            current = heading(node)
            current && current.fetch(:name).casecmp?(name)
          end
        raise MissingSource if index.blank?

        [index, heading(nodes.fetch(index)).fetch(:level)]
      end

      def heading(node)
        element =
          (
            if node.matches?("h2, h3, h4, h5, h6")
              node
            else
              node.at_css("h2, h3, h4, h5, h6")
            end
          )
        return if element.blank?

        {
          name: element.text.squish.delete_suffix("[edit]").squish,
          level: element.name.delete_prefix("h").to_i
        }
      end

      def excluded?(text)
        @excluded_patterns.any? { |pattern| text.to_s.match?(pattern) }
      end

      def split_blocks(blocks)
        raise MissingSource if blocks.length < 2

        midpoint = (blocks.length / 2.0).ceil
        [blocks.first(midpoint).join("\n"), blocks.drop(midpoint).join("\n")]
      end

      def snapshot_url(page)
        "#{ARCHIVE_ORIGIN}/web/#{page.fetch(:snapshot_at)}id_/#{source_url(page)}"
      end

      def source_url(page)
        "#{SOURCE_ORIGIN}/wiki/#{escape_path(page.fetch(:slug))}"
      end

      def history_url(page)
        "#{SOURCE_ORIGIN}/index.php?#{URI.encode_www_form(title: page.fetch(:slug), action: "history")}"
      end

      def revision_url(page)
        "#{SOURCE_ORIGIN}/index.php?#{URI.encode_www_form(title: page.fetch(:slug), oldid: page.fetch(:revision_id))}"
      end

      def escape_path(value)
        URI::DEFAULT_PARSER.escape(value.to_s)
      end

      def plugin_version
        Discourse.plugins_by_name["where-is-my-friends"]&.metadata&.version ||
          "unknown"
      end
    end
  end
end
