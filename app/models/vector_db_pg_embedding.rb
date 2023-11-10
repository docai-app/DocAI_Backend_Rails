# frozen_string_literal: true

class VectorDbPgEmbedding < ApplicationRecord
  establish_connection :vector_db
  self.table_name = 'langchain_pg_embedding'
end
