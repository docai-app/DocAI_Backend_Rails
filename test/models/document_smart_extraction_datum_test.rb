# frozen_string_literal: true

# == Schema Information
#
# Table name: document_smart_extraction_data
#
#  id                         :uuid             not null, primary key
#  data                       :jsonb
#  document_id                :uuid             not null
#  smart_extraction_schema_id :uuid             not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  status                     :integer          default("awaiting")
#  is_ready                   :boolean          default(FALSE)
#  retry_count                :integer          default(0)
#  meta                       :jsonb
#
# Indexes
#
#  index_smart_extraction_data_on_smart_extraction_schema_id  (smart_extraction_schema_id)
#
require 'test_helper'

class DocumentSmartExtractionDatumTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
