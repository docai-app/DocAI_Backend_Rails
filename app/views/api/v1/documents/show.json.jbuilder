json.data do
  json.extract! @document, :id, :name, :storage_url, :status, :content, :created_at, :updated_at
end