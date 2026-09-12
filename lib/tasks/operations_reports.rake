namespace :operations_reports do
  desc 'Restore reporting triggers after db:schema:load (does not backfill or send)'
  task install_triggers: :environment do
    Apartment::Tenant.switch('public') do
      require Rails.root.join('db/migrate/20260912001000_create_operations_reporting').to_s
      CreateOperationsReporting.new.install_triggers
    end
  end

  desc 'Read-only reporting readiness check; no mail or jobs are sent'
  task check: :environment do
    Apartment::Tenant.switch('public') do
      OperationsStatusReport.verify_capture!
      column = EssayOperationEvent.columns.find { |c| c.name == 'occurred_at' }
      raise 'Report timestamps are not offset-aware; apply reporting hardening migration' unless column&.sql_type&.include?('with time zone')
      raise 'Notification delivery tracking missing; apply reporting hardening migration' unless EssayGenerationNotification.table_exists?
      raise 'Report delivery tracking missing' unless OperationsReportDelivery.table_exists?
      raise 'Reporting disabled' unless ENV['AI_ENGLISH_REPORTS_ENABLED'] == 'true'
      Time.iso8601(ENV.fetch('AI_ENGLISH_REPORTS_ENABLED_AT'))
      raise 'No recipient' if ENV.fetch('ADMIN_NOTIFICATION_EMAIL', 'Bobby.lian@docai.net').blank?
      puts 'Tables, event capture, enablement and activation timestamp present. SMTP and worker runtime still require acceptance.'
    end
  end
end
