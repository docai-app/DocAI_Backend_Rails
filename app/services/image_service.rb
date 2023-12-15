# frozen_string_literal: true

class ImageService
  def self.html2Png(html)
    case ENV['RAILS_ENV']
    when 'production'
      Selenium::WebDriver::Chrome.path = '/usr/local/bin/chromedriver'
    when 'development'
      Selenium::WebDriver::Chrome.path = '/usr/local/bin/chromedriver'
    end

    # Webdrivers::Chromedriver.required_version = "114.0.5735.90"

    browser = Watir::Browser.new(:chrome, options: { args: ['allowed-ips', '--disable-dev-shm-usage', '--headless', '--hide-scrollbars', '--no-sandbox'] })

    browser.goto("data:text/html;base64,#{Base64.strict_encode64(html)}")

    previous_height = 0
    current_height = browser.execute_script('return document.body.scrollHeight')

    while current_height != previous_height
      previous_height = current_height
      browser.window.resize_to(1024, current_height)
      sleep(1)

      current_height = browser.execute_script('return document.body.scrollHeight')
    end

    temp_file = Tempfile.new(['screenshot', '.png'])

    browser.screenshot.save(temp_file.path)

    browser.close

    base64_screenshot = Base64.strict_encode64(File.read(temp_file.path))

    temp_file.close
    temp_file.unlink

    base64_screenshot
  end
end
