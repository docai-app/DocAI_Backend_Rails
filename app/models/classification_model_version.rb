# frozen_string_literal: true

# == Schema Information
#
# Table name: classification_model_versions
#
#  id                        :uuid             not null, primary key
#  classification_model_name :string           not null
#  entity_name               :string           not null
#  description               :string           default("")
#  pervious_version_id       :uuid
#  meta                      :jsonb
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#
# Indexes
#
#  index_classification_model_versions_on_entity_name          (entity_name)
#  index_classification_model_versions_on_pervious_version_id  (pervious_version_id)
#
class ClassificationModelVersion < ApplicationRecord
end
