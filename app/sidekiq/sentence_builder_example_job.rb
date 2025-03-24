# frozen_string_literal: true

class SentenceBuilderExampleJob
  include Sidekiq::Worker

  def perform(essay_assignment_id)
    essay_assignment = EssayAssignment.find(essay_assignment_id)

    # 確保 category 是 sentence_builder 並且 vocabs 存在
    if essay_assignment.category == 'sentence_builder' && essay_assignment.vocabs.present?
      # app_key = ENV['sentence_builder_example_app_key']
      # vocabs = essay_assignment.vocabs

      # 使用 SentenceBuilderExampleService 生成例句
      service = SentenceBuilderExampleService.new(essay_assignment.general_user_id, essay_assignment)
      examples = service.generate_examples

      if examples
        essay_assignment.update(vocab_examples: examples)
      else
        Rails.logger.error("Failed to generate vocab examples for EssayAssignment ID: #{essay_assignment_id}")
      end
    else
      Rails.logger.info("EssayAssignment ID: #{essay_assignment_id} is not a sentence_builder or has no vocabs.")
    end
  end
end
