# frozen_string_literal: true

# == Schema Information
#
# Table name: tags
#
#  id             :uuid             not null, primary key
#  name           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  taggings_count :integer          default(0)
#  is_checked     :boolean          default(FALSE)
#  folder_id      :uuid
#  user_id        :uuid
#  meta           :jsonb
#
class Tag < ApplicationRecord
  has_many :tag_functions, dependent: :destroy, class_name: 'TagFunction', foreign_key: 'tag_id'
  has_many :functions, through: :tag_functions, class_name: 'Function', foreign_key: 'function_id'
  has_many :taggings, dependent: :destroy, class_name: 'ActsAsTaggableOn::Tagging', foreign_key: 'tag_id'
  has_many :smart_extraction_schemas, class_name: 'SmartExtractionSchema', foreign_key: 'label_id'
  has_one :folder, class_name: 'Folder', foreign_key: 'folder_id'
  has_one :form_schema, class_name: 'FormSchema', foreign_key: 'label_id'

  def smart_extraction_schemas_count
    smart_extraction_schemas.count
  end
end
