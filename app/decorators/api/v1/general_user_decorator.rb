# frozen_string_literal: true

module Api
  module V1
    class GeneralUserDecorator < ApplicationDecorator
      delegate_all

      # Define presentation-specific methods here. Helpers are accessed through
      # `helpers` (aka `h`). You can override attributes, for example:
      #
      #   def created_at
      #     helpers.content_tag :span, class: 'time' do
      #       object.created_at.strftime("%a %m/%d/%y")
      #     end
      #   end
    end
  end
end