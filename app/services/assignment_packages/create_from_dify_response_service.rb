# frozen_string_literal: true

module AssignmentPackages
  class CreateFromDifyResponseService
    SUPPORTED_ASSIGNMENT_KEYS = %w[
      title topic assignment hints category rubric meta answer_visible remark essay_type
    ].freeze

    def initialize(assignment_package:, dify_response:)
      @assignment_package = assignment_package
      @dify_response = dify_response
    end

    def call
      payload = extract_payload
      assignments = Array(payload['assignments']).filter_map { |item| normalize_assignment_payload(item) }

      raise ArgumentError, 'Dify response did not include any supported assignments.' if assignments.empty?

      AssignmentPackage.transaction do
        old_assignments = @assignment_package.essay_assignments.to_a
        @assignment_package.assignment_package_items.destroy_all
        old_assignments.each(&:destroy)

        @assignment_package.update!(
          title: payload['title'].presence || @assignment_package.title,
          description: payload['description'],
          summary: payload['summary'].is_a?(Hash) ? payload['summary'] : {},
          dify_response: @dify_response,
          error: {},
          status: :active
        )

        assignments.each_with_index do |assignment_payload, index|
          assignment = create_assignment!(assignment_payload)
          @assignment_package.assignment_package_items.create!(
            essay_assignment: assignment,
            position: index + 1,
            status: index.zero? ? :available : :locked,
            unlocked_at: index.zero? ? Time.current : nil,
            title: assignment.title,
            category: assignment.category,
            meta: { 'dify_position' => assignment_payload['position'] }.compact
          )
        end

        @assignment_package.refresh_progress!
      end

      @assignment_package
    end

    private

    def extract_payload
      raw = @dify_response
      outputs = raw.dig('data', 'outputs') if raw.is_a?(Hash)

      candidate = if outputs.is_a?(Hash)
                    outputs['json'] || outputs['data'] || outputs['text'] || outputs
                  elsif raw.is_a?(Hash)
                    raw['json'] || raw['data'] || raw['text'] || raw
                  else
                    raw
                  end

      parse_json_candidate(candidate)
    end

    def parse_json_candidate(candidate)
      return candidate.deep_stringify_keys if candidate.is_a?(Hash)

      text = candidate.to_s.strip
      text = text.sub(/\A```(?:json)?/i, '').sub(/```\z/, '').strip
      JSON.parse(text).deep_stringify_keys
    rescue JSON::ParserError => e
      raise ArgumentError, "Dify response JSON is invalid: #{e.message}"
    end

    def normalize_assignment_payload(item)
      return nil unless item.is_a?(Hash)

      normalized = item.deep_stringify_keys.slice(*SUPPORTED_ASSIGNMENT_KEYS, 'position')
      category = normalized['category'].to_s
      return nil unless EssayAssignment.categories.key?(category)

      normalized['category'] = category
      normalized['title'] = normalized['title'].presence || normalized['topic'].presence || 'Practice Assignment'
      normalized['topic'] = normalized['topic'].presence || normalized['title']
      normalized['assignment'] = normalized['assignment'].presence || normalized['topic']
      normalized['rubric'] = normalized['rubric'].is_a?(Hash) ? normalized['rubric'] : default_rubric_for(category)
      normalized['meta'] = normalized['meta'].is_a?(Hash) ? normalized['meta'] : {}
      normalized
    end

    def default_rubric_for(category)
      return { 'name' => 'Talk Lab Speaking' } if category == 'talk_lab_speaking'

      { 'name' => category.to_s.titleize }
    end

    def create_assignment!(payload)
      @assignment_package.general_user.essay_assignments.create!(
        title: payload['title'],
        topic: payload['topic'],
        assignment: payload['assignment'],
        hints: payload['hints'],
        category: payload['category'],
        rubric: payload['rubric'],
        meta: package_assignment_meta(payload['meta']),
        answer_visible: payload.key?('answer_visible') ? payload['answer_visible'] : true,
        remark: payload['remark'],
        essay_type: payload['essay_type']
      )
    end

    def package_assignment_meta(meta)
      meta.deep_stringify_keys.merge(
        'source_type' => 'assignment_package',
        'assignment_package_id' => @assignment_package.id
      )
    end
  end
end
