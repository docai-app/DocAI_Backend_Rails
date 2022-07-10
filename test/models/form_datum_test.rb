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
require "test_helper"

class FormDatumTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
