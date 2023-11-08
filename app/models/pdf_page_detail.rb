# frozen_string_literal: true

class PdfPageDetail < ApplicationRecord
  belongs_to :document

  enum status: %i[pending processing completed failed]

  def retry_processing
    if retry_count < 3
      increment!(:retry_count)
      update(status: 'pending')
    else
      update(status: 'failed')
    end
  end

  def mark_completed
    update(status: 'completed', retry_count: 0)
  end

  def mark_failed
    update(status: 'failed')
  end
end
