# frozen_string_literal: true

module Api
  module V1
    class ConceptmapsController < ApiController
      def index; end

      def taxo_creator
        binding.pry

        Conceptmap.where(name: params[:name])
      end
    end
  end
end
