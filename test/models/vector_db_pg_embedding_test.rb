# frozen_string_literal: true

# == Schema Information
#
# Table name: langchain_pg_embedding
#
#  uuid          :uuid             not null, primary key
#  collection_id :uuid
#  embedding     :vector(1536)
#  document      :string
#  cmetadata     :json
#  custom_id     :string
#
require 'test_helper'

class VectorDbPgEmbeddingTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
