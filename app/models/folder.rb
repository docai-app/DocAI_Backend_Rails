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

  paginates_per 20

  def set_permissions_to_owner
    return if self['user_id'].nil?

    user.add_role :r, self
    user.add_role :w, self
  end

  def share_with(other)

    # if user has permission to share folder, then add role to other user
    return unless user.has_role? :w, self

    other.add_role :r, self
    other.add_role :w, self
  end
  
    

  # def set_sub_folder(sf)
  #   sf.update(ancestry: self['id'])
  # end

end
