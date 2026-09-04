# frozen_string_literal: true

module AssignmentPackages
  class GradingScoreSnapshot
    def self.for(essay_grading, category: nil)
      new(essay_grading, category: category).call
    end

    def initialize(essay_grading, category: nil)
      @essay_grading = essay_grading
      @category = category || essay_grading&.essay_assignment&.category
    end

    def call
      return empty unless @essay_grading.present? && @category.present?

      payload = EssayGradingSubmissionPayloadBuilder.call(@essay_grading, assignment_category: @category)
      score = numeric(payload&.dig(:score) || payload&.dig(:overall_score))
      full_score = numeric(payload&.dig(:full_score) || payload&.dig(:the_full_score))

      if score.nil?
        fallback = extract_talk_lab_score_payload
        score = numeric(fallback[:score]) if fallback[:score].present?
        full_score = numeric(fallback[:full_score]) if fallback[:full_score].present?
      end

      score = numeric(@essay_grading.read_attribute(:score)) if score.nil? && @essay_grading.read_attribute(:score).present?

      {
        score: score,
        full_score: full_score,
        score_label: build_score_label(score, full_score),
        status: @essay_grading.status
      }
    end

    private

    def empty
      {
        score: nil,
        full_score: nil,
        score_label: nil,
        status: nil
      }
    end

    def extract_talk_lab_score_payload
      grading_hash = @essay_grading.grading.is_a?(Hash) ? @essay_grading.grading.deep_stringify_keys : {}
      score_payload = grading_hash.dig('data', 'score')
      return {} unless score_payload.is_a?(Hash)

      {
        score: score_payload['overall_score'],
        full_score: score_payload['full_score']
      }
    end

    def numeric(value)
      return nil if value.nil? || value.to_s.strip.empty? || value.to_s == 'null'

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def build_score_label(score, full_score)
      return nil if score.nil?

      full_score.present? ? "#{format_number(score)}/#{format_number(full_score)}" : format_number(score)
    end

    def format_number(value)
      numeric = Float(value)
      numeric == numeric.to_i ? numeric.to_i.to_s : numeric.round(1).to_s
    rescue ArgumentError, TypeError
      value.to_s
    end
  end
end
