# frozen_string_literal: true

require 'json'

module TalkLabSpeaking
  module DifyMock
    # Static fixtures for Talk Lab Dify workflows. PM may edit copy here during mock phase.
    module Responses
      MOCK_SOURCE = 'talk_lab_dify_mock'

      PACKAGE_ASSIGNMENTS = [
        {
          'position' => 1,
          'category' => 'talk_lab_speaking',
          'title' => 'Warm-up: introduce yourself',
          'topic' => 'Self introduction',
          'assignment' => 'Have a short conversation introducing yourself and your interests.',
          'hints' => 'Use present simple. Keep answers to 2-3 sentences.',
          'meta' => {
            'talk_lab_speaking' => {
              'scenario' => 'Meeting a new classmate',
              'role' => 'Student',
              'objectives' => %w[fluency basic grammar],
              'rtc_prompt_materials' => { 'context_notes' => 'Friendly tone only.' }
            }
          }
        },
        {
          'position' => 2,
          'category' => 'talk_lab_speaking',
          'title' => 'Talk about a recent trip',
          'topic' => 'Past travel',
          'assignment' => 'Describe a trip you took and what you enjoyed.',
          'hints' => 'Use past tense.',
          'meta' => {
            'talk_lab_speaking' => {
              'scenario' => 'Chat with a friend',
              'role' => 'Traveler',
              'objectives' => %w[past tense details],
              'rtc_prompt_materials' => {}
            }
          }
        },
        {
          'position' => 3,
          'category' => 'talk_lab_speaking',
          'title' => 'Discuss future plans',
          'topic' => 'Future plans',
          'assignment' => 'Talk about something you plan to do next month.',
          'hints' => 'Use going to / will.',
          'meta' => {
            'talk_lab_speaking' => {
              'scenario' => 'Planning weekend',
              'role' => 'Planner',
              'objectives' => ['future forms'],
              'rtc_prompt_materials' => {}
            }
          }
        },
        {
          'position' => 4,
          'category' => 'talk_lab_speaking',
          'title' => 'Give an opinion',
          'topic' => 'Opinions',
          'assignment' => 'Share your opinion on a hobby and explain why you like it.',
          'hints' => 'Use because / so.',
          'meta' => {
            'talk_lab_speaking' => {
              'scenario' => 'Casual debate',
              'role' => 'Speaker',
              'objectives' => %w[opinion reasons],
              'rtc_prompt_materials' => {}
            }
          }
        }
      ].freeze

      GRADING_TEXT_PAYLOAD = {
        'overall_score' => 78,
        'full_score' => 100,
        'overall_summary' => 'Good effort. You answered on topic with clear sentences.',
        'sentence1' => {
          'sentence' => 'I went to Japan last year.',
          'errors' => {}
        },
        'sentence2' => {
          'sentence' => 'I really enjoyed the food there.',
          'errors' => {
            'error1' => {
              'category' => 'Style',
              'word' => 'really',
              'corr' => 'especially',
              'message' => 'Consider a stronger adverb.',
              'severity' => 'low'
            }
          }
        },
        'priority_improvements' => [
          'Add linking words between ideas.',
          'Extend answers with one extra detail.'
        ]
      }.freeze

      GRADING_SCORE_PAYLOAD = {
        'overall_score' => 78,
        'full_score' => 100,
        'criteria' => {
          'Fluency and Coherence' => {
            'score' => 7,
            'full_score' => 9,
            'comment' => 'Generally fluent.'
          },
          'Lexical Resource' => {
            'score' => 7,
            'full_score' => 9,
            'comment' => 'Adequate vocabulary.'
          },
          'Grammatical Range and Accuracy' => {
            'score' => 6,
            'full_score' => 9,
            'comment' => 'Minor errors.'
          },
          'Pronunciation and Intelligibility' => {
            'score' => 7,
            'full_score' => 9,
            'comment' => 'Clear enough.'
          }
        }
      }.freeze

      GENERAL_CONTEXT_TEXT_PAYLOAD = {
        'studentFeedback' => {
          'overall' => 'You spoke clearly and stayed on topic. Your answers were understandable and relevant.',
          'detailedFeedback' => "Strengths:\n- You responded to follow-up questions.\n- You used complete sentences.\n\nNext steps:\n- Add one reason sentence to each answer.\n- Practice linking words: because, however, after that.",
          'sections' => [
            {
              'title' => 'Interaction',
              'content' => 'You maintained a natural back-and-forth with the tutor.'
            },
            {
              'title' => 'Next practice',
              'content' => 'Try a longer answer with past tense and opinions.'
            }
          ]
        },
        '_source' => MOCK_SOURCE
      }.freeze

      module_function

      def package_payload(template_title:)
        title = template_title.presence || 'Talk Lab'

        {
          'title' => "#{title} Practice Pack",
          'description' => 'A short speaking practice package generated during Dify mock phase.',
          'summary' => {
            'learner_goal' => 'Build fluency through sequenced Talk Lab conversations.',
            'recommended_level' => 'CEFR B1',
            'themes' => %w[daily conversation travel opinions]
          },
          'assignments' => PACKAGE_ASSIGNMENTS.map(&:deep_dup)
        }
      end

      def package_dify_response(inputs:)
        template_title = extract_template_title(inputs)
        payload = package_payload(template_title: template_title)

        Rails.logger.info("[TalkLabDifyMock] Returning mock package response for template_title=#{template_title}")

        {
          'data' => {
            'outputs' => {
              'text' => payload
            },
            '_source' => MOCK_SOURCE
          }
        }
      end

      def workflow_stream_chunks(stage:)
        outputs =
          case stage.to_s
          when 'grading'
            grading_outputs
          when 'general_context'
            general_context_outputs
          else
            raise ArgumentError, "Unsupported Talk Lab Dify mock stage: #{stage}"
          end

        Rails.logger.info("[TalkLabDifyMock] Returning mock #{stage} workflow stream chunks")

        [
          {
            'event' => 'workflow_finished',
            'data' => {
              'outputs' => outputs,
              '_source' => MOCK_SOURCE
            }
          }
        ]
      end

      def grading_outputs
        {
          'text' => GRADING_TEXT_PAYLOAD.to_json,
          'score' => GRADING_SCORE_PAYLOAD.deep_dup
        }
      end

      def general_context_outputs
        {
          'text' => GENERAL_CONTEXT_TEXT_PAYLOAD.to_json
        }
      end

      def extract_template_title(inputs)
        return inputs[:template_title].to_s.strip if inputs.is_a?(Hash) && inputs[:template_title].present?
        return inputs['template_title'].to_s.strip if inputs.is_a?(Hash) && inputs['template_title'].present?

        'Talk Lab'
      end
    end
  end
end
