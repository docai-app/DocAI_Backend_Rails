class AssessmentRecord < ApplicationRecord
  belongs_to :recordable, polymorphic: true
end
