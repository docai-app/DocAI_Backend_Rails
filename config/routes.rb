Rails.application.routes.draw do
  devise_for :users,
             controllers: {
               sessions: "users/sessions",
               registrations: "users/registrations",
             }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  namespace :api, :defaults => { :format => :json } do
    namespace :v1 do
      resource :documents do
        get ':id', to: 'documents#show'
        member do
          post ':id/approval', to: 'documents#approval'
        end
      end
    end
  end
end
