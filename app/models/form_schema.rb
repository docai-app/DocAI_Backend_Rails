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
#
class FormSchema < ApplicationRecord
  has_many :form_datum, class_name: 'FormDatum'
end
