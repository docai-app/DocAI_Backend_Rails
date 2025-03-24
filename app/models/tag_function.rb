# frozen_string_literal: true

# == Schema Information
#
# Table name: tag_functions
#
#  id          :uuid             not null, primary key
#  tag_id      :uuid             not null
#  function_id :uuid             not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tag_functions_on_function_id  (function_id)
#  index_tag_functions_on_tag_id       (tag_id)
#
class TagFunction < ApplicationRecord
  belongs_to :tag, optional: true, class_name: 'Tag', foreign_key: 'tag_id'
  belongs_to :function, optional: true, class_name: 'Function', foreign_key: 'function_id'
end
