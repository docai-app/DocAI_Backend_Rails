require "RMagick/RMagick2"
require "base64"

class FormProjectionService
  def self.formatMessage(message)
    if message === true
      return "✓"
    elsif message === false
      return ""
    else
      return message
    end
  end

  def self.drawText(img, x1, y1, x2, y2, message)
    text = Magick::Draw.new
    text.font = "#{Rails.root}/lib/fonts/TaipeiSans.ttf"
    message = formatMessage(message)
    # define the image file name
    img.annotate(text, x2 - x1, y2 - y1, x1, y1, message) do
      text.gravity = Magick::CenterGravity
      text.pointsize = 36 # Font size
      text.fill = "#000000" # Font color
      img.format = "png"
    end

    return img
  end

  # Create the projection image from the url
  # @param url: the url of the projection image
  # @return the projection image (Magick::Image)
  def self.createImageFromUrl(url)
    img = Magick::ImageList.new(url)
    return img
  end

  # Export the projection image to base64
  # @param img: the projection image (Magick::Image)
  # @return the base64 string
  def self.exportImage2Base64(img)
    base64 = Base64.encode64(img.to_blob).gsub(/\s+/, "")
    return base64
  end

  # Export the projection image to blob
  # @param img: the data to be projected (Magick::Image)
  # @return the projection image (File)
  def self.exportImage2Blob(img)
    img.format = "png"
    img.write("projection.png")
    return File.open("projection.png", "rb")
  end

  # convert boundingBoxes to x1, y1, x2, y2, the boundingBoxes is array with 8 elements
  # @param boundingBoxes: the boundingBoxes array
  # @param img: the image
  # @return x1, y1, x2, y2
  def self.convertBoundingBoxes(boundingBoxes, img)
    x1 = boundingBoxes[0] * img.columns
    y1 = boundingBoxes[1] * img.rows
    x2 = boundingBoxes[2] * img.columns
    y2 = boundingBoxes[5] * img.rows
    return x1, y1, x2, y2
  end

  # Preview the form projection
  # @param form_schema: the form schema
  # @param data: the data to be projected
  # @return the projection image (Magick::Image)
  def self.preview(form_schema, data)
    formFields = form_schema.form_fields
    formProjection = form_schema.form_projection
    projectionImage = createImageFromUrl(form_schema.projection_image_url)

    formFields.each do |field|
      fieldIndex = formFields.index(field)
      fieldKey = field["fieldKey"]
      # Get a item from data which has the key name same as the fieldKey
      if data.has_key?(fieldKey) && !data[fieldKey].is_a?(Array)
        formProjectionItem = formProjection.find { |item| item["label"] == fieldKey }
        if formProjectionItem
          coordinates = convertBoundingBoxes(formProjectionItem["value"][0]["boundingBoxes"][0], projectionImage)
          projectionImage = drawText(projectionImage, coordinates[0], coordinates[1], coordinates[2], coordinates[3], data[fieldKey])
        else
          next
        end
      elsif data.has_key?(fieldKey) && data[fieldKey].is_a?(Array)
        # Loop the data[fieldKey] and get the item and index
        data[fieldKey].each_with_index do |tableItem, row|
          # loop the item object and get the key, value and index
          tableItem.to_unsafe_h.each_with_index do |(key, value), col|
            formProjectionItem = formProjection.find { |item| item["label"] == "#{fieldKey}/#{row + 1}/#{col}" }
            if formProjectionItem
              coordinates = convertBoundingBoxes(formProjectionItem["value"][0]["boundingBoxes"][0], projectionImage)
              projectionImage = drawText(projectionImage, coordinates[0], coordinates[1], coordinates[2], coordinates[3], value)
            else
              next
            end
          end
        end
      else
        next
      end
    end

    return projectionImage
  end
end
