# frozen_string_literal: true

require 'pdf-reader'

class PdfPageDetailService
  def self.process(document, subdomain)
    PdfPagesCreationJob.perform_async(document.id, subdomain)
  end
end
