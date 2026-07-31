# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class ContentProcessor
      Segment = Struct.new(:id, :kind, :text, keyword_init: true)
      ProcessedContent =
        Struct.new(
          :title,
          :segments,
          :redactions,
          :word_count,
          keyword_init: true
        )

      BLOCK_SELECTOR = "p, li, pre, h1, h2, h3, h4, h5, h6"
      EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
      PHONE_PATTERN = /(?<!\w)(?:\+?\d[\d ().-]{7,}\d)(?!\w)/
      HANDLE_PATTERN = /(?<!\w)@[A-Za-z0-9_]{2,32}\b/
      STREET_PATTERN =
        /\b\d{1,6}\s+[A-Za-z0-9.' -]{1,60}\s(?:Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct)\b/i
      CHINESE_ADDRESS_PATTERN =
        /[\p{Han}]{2,20}(?:路|街|巷|道)\d{1,5}号(?:\d{1,4}(?:室|房))?/

      def call(document)
        redactions = []
        segments = []
        segments.concat(
          process_html(document.fetch(:question_html), "question", redactions)
        )
        segments.concat(
          process_html(document.fetch(:answer_html), "answer", redactions)
        )
        words =
          segments.sum do |segment|
            segment.text.scan(/[A-Za-z]+(?:['’-][A-Za-z]+)*/).length
          end

        ProcessedContent.new(
          title: clean_text(document.fetch(:title).to_s, redactions),
          segments: segments,
          redactions: redactions.uniq,
          word_count: words
        )
      end

      private

      def process_html(html, kind, redactions)
        fragment = Nokogiri::HTML5.fragment(html.to_s)
        if fragment.css("img, picture, figure").any?
          redactions << "image"
          fragment.css("img, picture, figure").remove
        end
        fragment
          .css("blockquote")
          .each do |quote|
            next if quote.text.scan(/[A-Za-z]+(?:['’-][A-Za-z]+)*/).length <= 50

            redactions << "long_quote"
            quote.remove
          end

        blocks =
          fragment
            .css(BLOCK_SELECTOR)
            .reject do |node|
              node.ancestors.any? do |ancestor|
                ancestor.element? && ancestor.matches?(BLOCK_SELECTOR)
              end
            end
        blocks = [fragment] if blocks.empty? && fragment.text.present?
        index = 0
        blocks.filter_map do |node|
          text = clean_text(render_inline(node), redactions)
          next if text.blank?

          index += 1
          Segment.new(
            id: format("%s_%02d", kind, index),
            kind: kind,
            text: text
          )
        end
      end

      def render_inline(node)
        node
          .children
          .map do |child|
            if child.text?
              child.text
            elsif child.name == "a" && child["href"].present?
              "[#{child.text.strip}](#{child["href"]})"
            else
              render_inline(child)
            end
          end
          .join
      end

      def clean_text(value, redactions)
        text = value.gsub(/\s+/, " ").strip
        text =
          replace(
            text,
            EMAIL_PATTERN,
            "[已删除联系方式]",
            "contact_information",
            redactions
          )
        text =
          replace(
            text,
            PHONE_PATTERN,
            "[已删除联系方式]",
            "contact_information",
            redactions
          )
        text =
          replace(
            text,
            HANDLE_PATTERN,
            "[已删除联系方式]",
            "contact_information",
            redactions
          )
        text =
          replace(
            text,
            STREET_PATTERN,
            "[已删除精确地址]",
            "exact_address",
            redactions
          )
        replace(
          text,
          CHINESE_ADDRESS_PATTERN,
          "[已删除精确地址]",
          "exact_address",
          redactions
        )
      end

      def replace(text, pattern, replacement, reason, redactions)
        return text unless text.match?(pattern)

        redactions << reason
        text.gsub(pattern, replacement)
      end
    end
  end
end
