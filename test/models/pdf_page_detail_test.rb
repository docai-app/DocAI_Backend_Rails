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
require 'test_helper'

class PdfPageDetailTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
