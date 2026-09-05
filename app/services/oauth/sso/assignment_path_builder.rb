# frozen_string_literal: true

module Oauth
  module Sso
    class AssignmentPathBuilder
      CATEGORY_ROUTES = {
        'essay' => '/essay/upload',
        'comprehension' => '/comprehension/upload',
        'listening' => '/listening/upload',
        'speaking_conversation' => '/speaking/conversation/upload',
        'speaking_essay' => '/speaking/essay/upload',
        'sentence_builder' => '/sentence_building/upload',
        'speaking_pronunciation' => '/speaking_pronunciation/upload',
        'sentence_puzzle' => '/sentence_puzzle/upload',
        'talk_lab_speaking' => '/talk_lab_speaking/upload'
      }.freeze

      def self.path_for(assignment)
        prefix = CATEGORY_ROUTES[assignment.category.to_s] || '/essay/upload'
        code = assignment.code.to_s
        raise Error.new('ASSIGNMENT_UNAVAILABLE', 'Assignment code is missing.', http_status: 409) if code.blank?

        "#{prefix}/#{CGI.escape(code)}?embed=1"
      end

      def self.absolute_url_for(assignment)
        base = ENV.fetch('AIENGLISH_PUBLIC_ORIGIN',
                         ENV.fetch('FRONTEND_URL',
                                   ENV.fetch('AIENGLISH_WEB_ORIGIN', 'https://docai.m2mda.com')))
        "#{base.to_s.chomp('/')}#{path_for(assignment)}"
      end
    end
  end
end
