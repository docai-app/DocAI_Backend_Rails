# frozen_string_literal: true

# == Schema Information
#
# Table name: public.cors
#
#  id          :uuid             not null, primary key
#  name        :string           not null
#  description :string           default("")
#  url         :string           not null
#  meta        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Cors < ApplicationRecord
end
