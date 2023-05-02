class TagFunctionMappingService
  def self.mappping(document_id, tag_id)
    @document = Document.find(document_id)
    @tag = Tag.find(tag_id)
    @functions = @tag.functions
    @functions.each do |function|
      case function.name
      when "normal_approval"
        FunctionService.normal_approval(@document)
      end
    end
  end

  # Mapping batch documents with tag function, this mapping function will call all of the function in the tag automatically, the result will be saved automatically.
  # @param document_ids [Array] array of document ids
  # @param tag_id [Integer] tag id
  def self.mappping_batch(document_ids, tag_id)
    @documents = Document.where(id: document_ids)
    @tag = Tag.find(tag_id)
    @functions = @tag.functions
    @functions.each do |function|
      case function.name
      when "normal_approval"
        @documents.each do |document|
          FunctionService.normal_approval(document)
        end
      when "form_understanding"
        @documents.each do |document|
          FunctionService.form_understanding(document)
        end
      end
    end
  end
end
