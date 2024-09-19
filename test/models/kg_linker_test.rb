# frozen_string_literal: true

# == Schema Information
#
# Table name: public.kg_linkers
#
#  id            :bigint(8)        not null, primary key
#  map_from_type :string           not null
#  map_to_type   :string           not null
#  meta          :jsonb            not null
#  relation      :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  map_from_id   :uuid
#  map_to_id     :uuid
#
# Indexes
#
#  index_kg_linkers_on_map_from_id  (map_from_id)
#  index_kg_linkers_on_map_to_id    (map_to_id)
#
require 'test_helper'

class KgLinkerTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
