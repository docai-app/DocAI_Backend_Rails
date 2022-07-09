class DocumentApproval < ApplicationRecord
  belongs_to :document
  belongs_to :user

  enum status: [:awaiting, :approved, :rejected]
end
