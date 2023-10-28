# frozen_string_literal: true

class DocumentService
  # Set document type is pdf, image, txt and markdown file
  @documentType = ['application/pdf', 'image/jpeg', 'image/png', 'image/jpg']
  @documentExtension = ['.pdf', '.jpeg', '.png', '.jpg']
  @textDocumentType = ['text/plain', 'text/markdown']
  @textDocumentExtension = ['.txt', '.md']

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

  def self.checkFileIsTextDocument(file)
    # Check file type is text document
    puts file.content_type
    return true if @textDocumentType.include?(file.content_type)

    false
  end

  def self.checkFileUrlIsTextDocument(file_url)
    # Check file type is text document
    return true if @textDocumentExtension.include?(File.extname(file_url))

    false
  end

  def self.readTextDocument2Text(file)
    content = ''
    case file.content_type
    when 'text/plain'
      File.open(file, 'r') do |f|
        f.each_line do |line|
          content += line
        end
      end
    when 'text/markdown'
      File.open(file, 'r') do |f|
        f.each_line do |line|
          content += line
        end
      end
    end
    content
  end
end
