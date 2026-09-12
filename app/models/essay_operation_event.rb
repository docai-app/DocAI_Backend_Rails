class EssayOperationEvent < ApplicationRecord
  # This timestamp represents an instant, unlike the application's legacy local
  # timestamp columns. Include the offset in binds even when AR defaults to :local.
  class InstantType < ActiveRecord::Type::DateTime
    def serialize(value)
      cast(value)&.iso8601(6)
    end
  end
  attribute :occurred_at, InstantType.new
  belongs_to :essay_grading
end
