# frozen_string_literal: true

class ChangeEssayAssignmentRubic < ActiveRecord::Migration[7.0]
  def up
    EssayAssignment.find_each do |assignment|
      if assignment.rubric['app_key'].is_a?(String)
        assignment.rubric['app_key'] = {
          'grading' => assignment.rubric['app_key'],
          'general_context' => nil
        }
        assignment.save(validate: false)
      end
    end
  end

  def down
    EssayAssignment.find_each do |assignment|
      if assignment.rubric['app_key'].is_a?(Hash)
        assignment.rubric['app_key'] = assignment.rubric['app_key']['grading']
        assignment.save(validate: false)
      end
    end
  end
end
