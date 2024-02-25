# frozen_string_literal: true

# == Schema Information
#
# Table name: public.classification_model_versions
#
#  id                  :uuid             not null, primary key
#  model_name          :string           not null
#  entity_name         :string           not null
#  description         :string           default("")
#  pervious_version_id :uuid
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class ClassificationModelVersion < ApplicationRecord
end
