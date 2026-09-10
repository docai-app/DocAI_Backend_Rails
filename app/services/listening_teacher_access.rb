# frozen_string_literal: true

class ListeningTeacherAccess
  def self.allowed?(user, embed: false)
    return false if embed || !user
    user.aienglish_global_admin? ||
      (%w[teacher school_admin].include?(user.aienglish_role) && user.aienglish_features_list.include?('listening'))
  end
end
