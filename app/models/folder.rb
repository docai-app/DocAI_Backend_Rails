# == Schema Information
#
# Table name: folders
#
#  id         :uuid             not null, primary key
#  name       :string
#  parent_id  :uuid
#  user_id    :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Folder < ApplicationRecord
  resourcify
  acts_as_tree
  
  belongs_to :user

  after_create :set_permissions_to_owner

  def set_permissions_to_owner
    return if self['user_id'].nil?

    user.add_role :r, self
    user.add_role :w, self
  end

  # def set_sub_folder(sf)
  #   sf.update(ancestry: self['id'])
  # end

end
