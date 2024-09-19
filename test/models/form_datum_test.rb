# frozen_string_literal: true

# == Schema Information
#
# Table name: form_datum
#
#  id             :uuid             not null, primary key
#  document_id    :uuid
#  form_schema_id :uuid
#  data           :jsonb
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_form_datum_on_document_id     (document_id)
#  index_form_datum_on_document_id     (document_id)
#  index_form_datum_on_form_schema_id  (form_schema_id)
#  index_form_datum_on_form_schema_id  (form_schema_id)
#
require 'test_helper'

class FormDatumTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
