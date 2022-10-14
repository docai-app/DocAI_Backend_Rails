class TagFunctionMappingService
    def self.mappping(document_id, tag_id)
        @document = Document.find(document_id)
        @tag = Tag.find(tag_id)
        @functions = @tag.functions
        @functions.each do |function|
            case function.name
            when 'normal_approval'
                FunctionService.normal_approval(@document)
            end
        end
    end
end