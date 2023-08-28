# frozen_string_literal: true

class Chatbot < ApplicationRecord
  enum category: %i[assistant]

  belongs_to :user, optional: true, class_name: 'User', foreign_key: 'user_id'
end
