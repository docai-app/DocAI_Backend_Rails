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
class FormSchema < ApplicationRecord
    has_many :form_datum, class_name: "FormDatum"
end
