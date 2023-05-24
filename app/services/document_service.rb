# frozen_string_literal: true

class DocumentService
  # Set document type is pdf and image file
  @documentType = ['application/pdf', 'image/jpeg', 'image/png', 'image/jpg']
  @documentExtension = ['.pdf', '.jpeg', '.png', '.jpg']

  def self.checkFileIsDocument(file)
    # Check file type is document
    return true if @documentType.include?(file.content_type)

    false
  end

  def self.checkFileUrlIsDocument(file_url)
    # Check file type is document
    return true if @documentExtension.include?(File.extname(file_url))

    false
  end
end
