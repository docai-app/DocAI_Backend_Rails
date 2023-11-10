# frozen_string_literal: true

class VectorDbPgCollection < ApplicationRecord
  establish_connection :vector_db
  self.table_name = 'langchain_pg_collection'
end
