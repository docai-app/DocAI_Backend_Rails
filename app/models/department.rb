# frozen_string_literal: true

# == Schema Information
#
# Table name: departments
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :string
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Department < ApplicationRecord
end
