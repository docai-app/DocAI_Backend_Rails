# frozen_string_literal: true

# == Schema Information
#
# Table name: langchain_pg_embedding
#
#  uuid          :uuid             not null, primary key
#  collection_id :uuid
#  embedding     :vector
#  document      :string
#  cmetadata     :json
#  custom_id     :string
#
# Foreign Keys
#
#  langchain_pg_embedding_collection_id_fkey  (collection_id => langchain_pg_collection.uuid) ON DELETE => cascade
#
require 'test_helper'

class VectorDbPgEmbeddingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
