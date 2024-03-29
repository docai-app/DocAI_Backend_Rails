# frozen_string_literal: true

Trestle.resource(:super_admins, model: SuperAdmin, scope: Auth) do
  menu do
    group :configuration, priority: :last do
      item :super_admins, icon: 'fas fa-users'
    end
  end

  table do
    column :avatar, header: false do |super_admin|
      avatar_for(super_admin)
    end
    column :email, link: true
    actions do |a|
      a.delete unless a.instance == current_user
    end
  end

  form do |_super_admin|
    text_field :email

    row do
      col(sm: 6) { password_field :password }
      col(sm: 6) { password_field :password_confirmation }
    end
  end

  # Ignore the password parameters if they are blank
  update_instance do |instance, attrs|
    if attrs[:password].blank?
      attrs.delete(:password)
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
    end

    instance.assign_attributes(attrs)
  end

  # Log the current user back in if their password was changed
  if Devise.sign_in_after_reset_password
    after_action on: :update do
      login!(instance) if instance == current_user && instance.encrypted_password_previously_changed?
    end
  end
end
