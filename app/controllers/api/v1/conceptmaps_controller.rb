
module Api
  module V1
    class ConceptmapsController < ApiController
      def index
      end

      def taxo_creator
        binding.pry
        
        taxo = Conceptmap.where(name: params[:name])
        
        
      end
    end
  end
end