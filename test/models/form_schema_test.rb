# frozen_string_literal: true

# == Schema Information
#
# Table name: form_schemas
#
#  id                   :uuid             not null, primary key
#  name                 :string
#  form_schema          :json
#  ui_schema            :json
#  data_schema          :jsonb
#  description          :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  azure_form_model_id  :string
#  is_ready             :boolean          default(FALSE), not null
#  form_fields          :jsonb
#  form_projection      :jsonb
#  can_project          :boolean          default(FALSE), not null
#  projection_image_url :string           default("")
#  label_id             :uuid
#
# Indexes
#
#  index_form_schemas_on_name  (name)
#  index_form_schemas_on_name  (name)
#
require 'test_helper'

class FormSchemaTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
