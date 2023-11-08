# frozen_string_literal: true

class PdfPageJob
  include Sidekiq::Job

  def perform(*args)
    # Do something
  end
end
