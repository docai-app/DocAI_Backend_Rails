# frozen_string_literal: true

# == Schema Information
#
# Table name: pdf_page_details
#
#  id            :uuid             not null, primary key
#  document_id   :uuid             not null
#  page_number   :integer
#  summary       :text
#  keywords      :string
#  status        :integer          default("pending"), not null
#  retry_count   :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  error_message :text
#
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
    update(status: 'failed', retry_count: retry_count + 1)
  end
end
