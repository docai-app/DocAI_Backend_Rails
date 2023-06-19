# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers
  before_action :switch_tenant
  before_action :set_paper_trail_whodunnit

  def switch_tenant
    subdomain = Utils.extractReferrerSubdomain(request.referrer)

    if Apartment.tenant_names.include?(subdomain)
      Apartment::Tenant.switch!(subdomain)
    elsif subdomain == 'localhost'
      Apartment::Tenant.switch!('public')
    else
      Apartment::Tenant.switch!('public')
    end
  end
end
