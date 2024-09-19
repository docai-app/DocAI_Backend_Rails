# frozen_string_literal: true

# == Schema Information
#
# Table name: public.essay_gradings
#
#  id                  :uuid             not null, primary key
#  essay               :text
#  topic               :string
#  status              :integer          default("pending"), not null
#  grading             :jsonb            not null
#  general_user_id     :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  essay_assignment_id :uuid
#  general_context     :jsonb            not null
#  using_time          :integer          default(0), not null
#  meta                :jsonb            not null
#
# Indexes
#
#  index_essay_gradings_on_essay_assignment_id  (essay_assignment_id)
#
# Foreign Keys
#
#  fk_rails_...  (essay_assignment_id => public.essay_assignments.id)
#  fk_rails_...  (general_user_id => public.general_users.id)
#
require 'test_helper'

class EssayGradingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
