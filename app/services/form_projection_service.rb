require "RMagick"
require "base64"

class FormProjectionService
    def self.drawText(img, x1, y1, x2, y2, message)
        text = Magick::Draw.new
        text.font_family = "helvetica" # Font file; needs to be absolute
        text.rectangle(x1, y1, x2, y2)
        text.fill = "#663399"
        text.draw(img)
        img.annotate(text, x2 - x1, y2 - y1, x1, y1, message) do
            text.gravity = Magick::CenterGravity
            text.pointsize = 36 # Font size
            text.fill = "#ffd700" # Font color
            img.format = "png"
        end
        return img
    end

    def self.createImageFromUrl(url)
        img = Magick::ImageList.new(url)
        return img
    end

    def self.exportImage2Base64(img)
        base64 = Base64.encode64(img.to_blob)
        return base64
    end
end