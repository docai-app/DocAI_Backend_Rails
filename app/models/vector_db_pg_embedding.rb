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
class VectorDbPgEmbedding < ApplicationRecord
  establish_connection :vector_db
  self.table_name = 'langchain_pg_embedding'

  def self.find_document_sentences_containing(keyword, schema, document_id)
    results = where('document LIKE ?', "%#{keyword}%").where("cmetadata->>'schema' = ?", schema).where("cmetadata->>'document_id' = ?", document_id).pluck(
      :document, :cmetadata
    )
    sentences_with_pages(results, keyword)
  end

  def self.sentences_containing_keyword(documents, keyword)
    documents.flat_map do |doc|
      doc.split(/\.|\?|!|。|？|！|，/).select { |sentence| sentence.include?(keyword) }.map(&:strip)
    end
  end

  def self.sentences_with_pages(results, keyword)
    results.each_with_object([]) do |(doc, metadata), sentences|
      page_number = metadata['page']
      sentences_in_doc = doc.split(/\.|\?|!|。|？|！|，/).select { |sentence| sentence.include?(keyword) }.map(&:strip)
      sentences_in_doc.each do |sentence|
        sentences << { sentence:, page: page_number }
      end
    end
  end
end
