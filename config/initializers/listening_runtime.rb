# frozen_string_literal: true

# Optional host-local, server-only Listening settings. Existing Azure settings
# used by other assignment types are deliberately not changed.
require 'json'
path = Rails.root.join('.listening-runtime.json')
if path.file?
  raise 'Listening runtime file must be private' unless (File.stat(path).mode & 0o077).zero?
  settings = JSON.parse(File.read(path))
  allowed = %w[QG_LISTENING_INTERNAL_URL QG_LISTENING_SERVICE_TOKEN QG_LISTENING_STORAGE_CONTAINER
    QG_LISTENING_AZURE_STORAGE_NAME QG_LISTENING_AZURE_STORAGE_ACCESS_KEY]
  raise 'Invalid Listening runtime configuration' unless settings.is_a?(Hash) &&
    (settings.keys - allowed).empty? && settings.values.all? { |value| value.is_a?(String) }
  settings.each { |key, value| ENV[key] = value unless ENV.key?(key) }
end
