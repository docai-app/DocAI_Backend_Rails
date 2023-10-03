# frozen_string_literal: true

class Ability < ApplicationRecord
  # include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)

    if user.has_role?(:admin)
      can :manage, :all
    else
      can :read, Document, department_id: user.department_id
      can :create, Document
      can :update, Document, user_id: user.id
      can :destroy, Document, user_id: user.id
    end
  end
end
