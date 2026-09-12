class OperationsReportDelivery < ApplicationRecord
  validates :period_start, :period_end, presence: true
end
