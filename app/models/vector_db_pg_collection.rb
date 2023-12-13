# frozen_string_literal: true

# == Schema Information
#
# Table name: langchain_pg_collection
#
#  uuid      :uuid             not null, primary key
#  name      :string
#  cmetadata :json
#
class VectorDbPgCollection < ApplicationRecord
  establish_connection :vector_db
  self.table_name = 'langchain_pg_collection'
end
