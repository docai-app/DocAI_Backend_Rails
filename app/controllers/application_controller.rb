# frozen_string_literal: true

class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers
  before_action :switch_tenant
  before_action :set_paper_trail_whodunnit

  def switch_tenant
    puts 'ApplicationController#switch_tenant'
    if params[:user]
      email = params[:user][:email]
      puts "email: #{email}"
      subdomain = email.split('@')[1].split('.')[0]
      puts "subdomain: #{subdomain}"
      tenantName = Utils.getTenantName(subdomain)
    elsif params[:general_user]
      puts "General User! #{params[:general_user][:email]}"
      tenantName = ENV['DEFAULT_TENANT_NAME']
    else
      tenantName = ENV['DEFAULT_TENANT_NAME']
    end
    puts "tenantName: #{tenantName}"
    begin
      Apartment::Tenant.switch!(tenantName)
      ActiveRecord::Base.connection.execute('SELECT 1')
    rescue Apartment::TenantNotFound
      render json: { success: false, message: 'Tenant not found.' }, status: :not_found
    end
  end
end
