# == Schema Information
#
# Table name: form_schemas
#
#  id          :uuid             not null, primary key
#  name        :string
#  form_schema :json
#  ui_schema   :json
#  data_schema :jsonb
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require "test_helper"

class FormSchemaTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
