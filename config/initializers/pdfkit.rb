PDFKit.configure do |config|
  config.wkhtmltopdf = '/usr/local/bin/wkhtmltopdf'
  config.verbose = true
  config.default_options[:page_size] = 'A4'
end
