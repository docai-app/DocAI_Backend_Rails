# frozen_string_literal: true

namespace :db do
  namespace :oauth do
    desc 'Remove stuck migration versions and re-apply OAuth + schools migrations (docai_prod recovery)'
    task reapply_pending_oauth: :environment do
      versions = %w[20260820000000 20260826120000]
      conn = ActiveRecord::Base.connection

      public_oauth_exists = lambda do
        conn.execute(<<~SQL.squish).first['exists']
          SELECT EXISTS (
            SELECT 1 FROM pg_tables
            WHERE schemaname = 'public' AND tablename = 'oauth_applications'
          )
        SQL
      end

      puts '== Checking public.oauth_applications =='
      puts public_oauth_exists.call ? 'EXISTS' : 'MISSING'

      delete_version = lambda do |label|
        versions.each do |v|
          conn.execute("DELETE FROM schema_migrations WHERE version = '#{v}'")
          puts "  #{label}: cleared #{v}"
        end
      end

      puts '== Removing schema_migrations rows (public) =='
      delete_version.call('public')

      if defined?(Apartment)
        puts '== Removing schema_migrations rows (tenants) =='
        Apartment.tenant_names.each do |tenant|
          Apartment::Tenant.switch(tenant) do
            delete_version.call(tenant)
          end
        end
        Apartment::Tenant.reset
      end

      puts '== Re-running db:migrate =='
      ActiveRecord.dump_schema_after_migration = false if ActiveRecord.respond_to?(:dump_schema_after_migration=)
      Rake::Task['db:migrate'].reenable
      Rake::Task['db:migrate'].invoke

      Apartment::Tenant.reset if defined?(Apartment)

      puts '== Done. Verify public.oauth_applications =='
      puts public_oauth_exists.call ? 'OK' : 'STILL MISSING — check migration on_public_schema? or run SQL manually'
    end
  end
end
