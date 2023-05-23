class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers
  before_action :set_paper_trail_whodunnit
  before_action :switch_tenant

  def switch_tenant
    subdomain = Utils.extractReferrerSubdomain(request.referrer)

    if Apartment.tenant_names.include?(subdomain)
      Apartment::Tenant.switch!(subdomain)
    else
      Apartment::Tenant.switch!("public")
    end
  end
end
