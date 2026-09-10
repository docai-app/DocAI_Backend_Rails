# frozen_string_literal: true

class ListeningPlaybackState < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
end
