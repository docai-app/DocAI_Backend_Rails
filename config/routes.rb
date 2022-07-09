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
      # **********Documents API**********
      resource :documents do
        get ":id", to: "documents#show"
        # Show documents by tag id
        get "tags/:tag_id", to: "documents#show_by_tag"
        member do
          post ":id/approval", to: "documents#approval"
        end
      end

      # **********Search API**********
      # Search documents by name like name param
      get "search/documents/name", to: "documents#show_by_name"
      # Search documents by content like content param
      get "search/documents/content", to: "documents#show_by_content"

      # **********Tags API**********
      get "tags", to: "tags#index"
      get "tags/:id", to: "tags#show"
      post "tags", to: "tags#create"
      put "tags/:id", to: "tags#update"

      # # **********Storage API**********
      # post "storage/upload", to: "storage#upload"

      # **********FormSchema API**********
      get "form/schemas", to: "form_schema#index"
      get "form/schemas/:id", to: "form_schema#show"
      get "form/schemas/name/:name", to: "form_schema#show_by_name"
    end
  end
end
