class DocumentService
  # Set document type is pdf and image file
  private documentType = ["application/pdf", "image/jpeg", "image/png", "image/jpg"]
  private documentExtension = [".pdf", ".jpeg", ".png", ".jpg"]

  def self.checkFileIsDocument(file)
    # Check file type is document
    if documentType.include?(file.content_type)
      return true
    else
      return false
    end
  end

  def self.checkFileUrlIsDocument(file_url)
    # Check file type is document
    if documentExtension.include?(File.extname(file_url))
      return true
    else
      return false
    end
  end
end
