# frozen_string_literal: true

module AssignmentPackages
  class GenerationService
    def initialize(assignment_package)
      @assignment_package = assignment_package
      @template = assignment_package.learning_path_template
    end

    def call
      raise ArgumentError, 'Learning path template is missing.' if @template.blank?

      inputs = generation_inputs
      @assignment_package.update!(dify_request: inputs, status: :generating, error: {})

      response = DifyGenerationClient.new(
        app_key: dify_app_key,
        user_id: @assignment_package.general_user_id
      ).call(inputs: inputs)

      CreateFromDifyResponseService.new(
        assignment_package: @assignment_package,
        dify_response: response
      ).call
    rescue StandardError => e
      @assignment_package.update!(
        status: :failed,
        error: {
          'message' => e.message,
          'error_class' => e.class.name,
          'occurred_at' => Time.current.iso8601
        }
      )
      raise
    end

    private

    def generation_inputs
      conversation = @assignment_package.source_conversation || {}

      {
        template: @template.as_student_json.to_json,
        template_title: @template.title,
        template_description: @template.description,
        prompt_config: @template.prompt_config.to_json,
        conversation: conversation.to_json,
        transcript: conversation['transcript'],
        turns: Array(conversation['turns']).to_json,
        student_audio_urls: Array(conversation['student_audio_urls']).to_json,
        ai_audio_urls: Array(conversation['ai_audio_urls']).to_json
      }.compact
    end

    def dify_app_key
      @template.dify_config['app_key'].presence ||
        @template.dify_config['package_generator_app_key'].presence ||
        ENV['ASSIGNMENT_PACKAGE_GENERATOR_APP_KEY'].presence ||
        ENV['assignment_package_generator_app_key'].presence
    end
  end
end
