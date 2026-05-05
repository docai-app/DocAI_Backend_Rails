# frozen_string_literal: true

module Api
  module School
    module V1
      class ProfilesController < SchoolApiController
        def show
          user = current_general_user
          render json: {
            success: true,
            data: {
              user: user.as_json(only: %i[id email nickname school_id created_at updated_at],
                                methods: []).merge('aienglish_role' => user.aienglish_role),
              school: user.school&.as_json(only: %i[id name code status])
            }
          }, status: :ok
        end
      end
    end
  end
end
