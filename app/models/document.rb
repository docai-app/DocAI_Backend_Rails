# == Schema Information
#
# Table name: documents
#
#  id          :uuid             not null, primary key
#  name        :string
#  storage_url :string
#  content     :text
#  status      :integer          default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Document < ApplicationRecord
  acts_as_taggable_on :labels
  enum status: [:pending, :uploaded, :confirmed]
end
