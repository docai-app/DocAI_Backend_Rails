# frozen_string_literal: true

# == Schema Information
#
# Table name: smart_extraction_schemas
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :string
#  label_id    :uuid
#  schema      :jsonb
#  data_schema :jsonb
#  user_id     :uuid
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  has_label   :boolean          default(FALSE), not null
#
# Indexes
#
#  index_smart_extraction_schemas_on_label_id  (label_id)
#  index_smart_extraction_schemas_on_label_id  (label_id)
#  index_smart_extraction_schemas_on_user_id   (user_id)
#  index_smart_extraction_schemas_on_user_id   (user_id)
#
require 'test_helper'

class SmartExtractionSchemaTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
