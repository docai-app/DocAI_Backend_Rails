# frozen_string_literal: true

class Tag < ApplicationRecord
  # acts_as_taggable_on :functions
  has_many :tag_functions, dependent: :destroy, class_name: 'TagFunction', foreign_key: 'tag_id'
  has_many :functions, through: :tag_functions, class_name: 'Function', foreign_key: 'function_id'
end
