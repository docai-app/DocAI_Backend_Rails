# frozen_string_literal: true

# == Route Map
#

Rails.application.routes.draw do
  mount Rswag::Api::Engine => '/api-docs'
  mount Rswag::Ui::Engine => '/api-docs'
  devise_for :super_admins
  require 'sidekiq/web'
  require 'sidekiq-scheduler/web'
  mount Sidekiq::Web => '/sidekiq'

  devise_for :users,
             controllers: {
               sessions: 'users/sessions',
               registrations: 'users/registrations',
               omniauth_callbacks: 'omniauth_callbacks'
             }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  devise_for :general_users, controllers: {
    sessions: 'general_users/sessions',
    registrations: 'general_users/registrations'
  }

  # Defines the root path route ("/")
  # root "articles#index"

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      # ********** Essay grading ********
      resources :essay_assignments, only: %i[index show create update destroy] do
        resources :essay_gradings, only: [:create]
        member do
          get 'read'
          get 'show_only'
          get 'download_reports', to: 'essay_gradings#download_reports'
          
        end
        collection do
          post :parse_vocab_csv
        end
      end
      resources :essay_gradings, only: %i[index show update destroy] do
        member do
          get 'download_report'
          get 'download_supplement_practice'
        end
      end

      # ********** Group API *********
      resources :groups do
        member do
          post 'add_students'
          post 'remove_students'
        end
      end

      # ********** LINKTREE API *********
      resources :link_sets do
        resources :links
      end

      # ********** TAXO API *********
      resources :conceptmaps do
        # member do
        #   get 'concept_options'
        #   get 'markdown'
        #   get 'qa_documents'
        #   get 'search_documents'
        #   get 'recommand_epaper'
        #   get 'nodes' # 比 taxo loader 用
        # end

        collection do
          # get 'dropdown_options'
          # get 'select_options'
          post 'taxo_creator'
        end
      end

      # **********做評估 API**********
      resources :assessment_records, only: %i[create index show update destroy] do
        collection do
          get 'students'
          get 'students/:uuid', to: 'assessment_records#show_student_assessments'
        end
      end

      # **********Documents API**********
      resources :documents, only: %i[index show update destroy] do
        collection do
          get 'collection', to: 'documents#show_by_ids', as: :show_documents_by_ids
          get 'latest/predict', to: 'documents#show_latest_predict'
          get ':date/predict', to: 'documents#show_specify_date_latest_predict'
          post 'deep_understanding', to: 'documents#deep_understanding'
          get 'pdf/page_details', to: 'documents#show_pdf_page_details'
          post 'pdf/search/keyword', to: 'documents#pdf_search_keyword'
          post ':id/qa', to: 'documents#qa'
        end

        member do
          post 'approval', to: 'documents#approval'
          get 'ocr', to: 'documents#ocr'
        end

        get 'tags/:tag_id', to: 'documents#show_by_tag', as: :show_documents_by_tag
      end

      # **********Search API**********
      # Search documents by name like name param
      get 'search/documents/name', to: 'documents#show_by_name'
      # Search documents by content like content param
      get 'search/documents/content', to: 'documents#show_by_content'
      # Search documents by date
      get 'search/documents/date', to: 'documents#show_by_date'
      # Search documents by tag and date
      get 'search/documents/tag_content', to: 'documents#show_by_tag_and_content'
      # Search form data by form schema name and date
      get 'search/form/:name/:date', to: 'form_datum#show_by_form_name_and_date'
      # Search form data by date
      get 'search/form/:date', to: 'form_datum#show_by_date'

      # **********Tags API**********
      get 'tags', to: 'tags#index'
      get 'tags/:id', to: 'tags#show'
      get 'tags/tagging/document', to: 'tags#show_by_tagging'
      get 'tags/:id/functions', to: 'tags#show_functions'
      post 'tags', to: 'tags#create'
      put 'tags/:id', to: 'tags#update'
      put 'tags/:id/features', to: 'tags#update_chain_features'
      post 'tags/function', to: 'tag_functions#create'
      delete 'tags/function', to: 'tag_functions#destroy'

      # **********Functions API**********
      get 'functions', to: 'functions#index'
      get 'functions/:id', to: 'functions#show'
      post 'functions', to: 'functions#create'
      put 'functions/:id', to: 'functions#update'

      # **********Storage API**********
      post 'storage/upload', to: 'storage#upload'
      post 'storage/upload/batch/tag', to: 'storage#upload_batch_tag'
      post 'storage/upload/directly', to: 'storage#upload_directly'
      post 'storage/upload/generated_content', to: 'storage#upload_generated_content'
      post 'storage/upload/chatbot', to: 'storage#chatbot_upload'
      post 'storage/upload/general_user_file', to: 'storage#upload_general_user_file'
      post 'storage/upload/general_user_file_by_url', to: 'storage#upload_general_user_file_by_url'

      # **********FormSchema API**********
      get 'form/schemas', to: 'form_schema#index'
      get 'form/schemas/:id', to: 'form_schema#show'
      get 'form/schemas/name/:name', to: 'form_schema#show_by_name'
      get 'form/schemas/status/ready', to: 'form_schema#show_ready'
      get 'form/schemas/status/project', to: 'form_schema#show_can_project'

      # **********FormDatum API**********
      get 'form/datum', to: 'form_datum#index'
      get 'form/datum/:id', to: 'form_datum#show'
      post 'form/datum/:form_schema_id/search', to: 'form_datum#show_by_filter_and_form_schema_id'
      put 'form/datum/:id', to: 'form_datum#update'
      delete 'form/datum/:id', to: 'form_datum#destroy'
      post 'form/datum/generate/chart', to: 'form_datum#generate_chart'

      # **********AbsenceForm API**********
      get 'form/absence/approval', to: 'absence_forms#show_by_approval_status'
      get 'form/absence/approval/:id', to: 'absence_forms#show_by_approval_id'
      post 'form/absence', to: 'absence_forms#upload'
      put 'form/absence/:id', to: 'absence_forms#update'
      get 'form/absence/recognition/:id', to: 'absence_forms#recognize_specific'

      # **********Classification API**********
      get 'classification/predict', to: 'classifications#predict'
      post 'classification/confirm', to: 'classifications#confirm'
      put 'classification', to: 'classifications#update_classification'

      # **********Statistics API**********
      get 'statistics/count/tags/:date', to: 'statistics#count_each_tags_by_date'
      get 'statistics/count/documents/:date', to: 'statistics#count_document_by_date'
      get 'statistics/count/documents/status/:date', to: 'statistics#count_document_status_by_date'

      # **********Document Approval API**********
      get 'approval/documents', to: 'document_approvals#index'
      get 'approval/documents/:id', to: 'document_approvals#show'
      get 'approval/normal/documents', to: 'document_approvals#show_normal_documents_by_approval_status'
      get 'approval/form/documents', to: 'document_approvals#show_forms_by_approval_status'
      put 'approval/documents/:id', to: 'document_approvals#update'

      # **********Folder API**********
      get 'folders', to: 'folders#index'
      get 'folders/:id', to: 'folders#show'
      get 'folders/:id/ancestors', to: 'folders#show_ancestors'
      post 'folders', to: 'folders#create'
      put 'folders/:id', to: 'folders#update'
      delete 'folders/:id', to: 'folders#destroy'
      post 'folders/documents', to: 'folders#add_document'

      # **********Drive API**********
      get 'drive/files', to: 'drive#index'
      get 'drive/files/:id', to: 'drive#show'
      post 'drive/folders/share', to: 'drive#share'
      post 'drive/items/move', to: 'drive#move_items'
      post 'drive/download_zip', to: 'drive#download_zip'

      # **********Form API**********
      post 'form/recognition', to: 'forms#recognize'

      # **********Project API**********
      get 'projects', to: 'projects#index'
      get 'projects/:id', to: 'projects#show'
      get 'projects/:id/tasks', to: 'projects#show_tasks'
      post 'projects', to: 'projects#create'
      put 'projects/:id', to: 'projects#update'
      delete 'projects/:id', to: 'projects#destroy'

      # **********Project Tasks API**********
      get 'tasks', to: 'project_tasks#index'
      get 'tasks/:id', to: 'project_tasks#show'
      post 'tasks', to: 'project_tasks#create'
      put 'tasks/:id', to: 'project_tasks#update'
      delete 'tasks/:id', to: 'project_tasks#destroy'

      # **********User API**********
      get 'users', to: 'users#index'
      get 'users/:id/profile', to: 'users#show'
      get 'users/me', to: 'users#show_current_user'
      put 'users/me/password', to: 'users#update_password'
      put 'users/me/profile', to: 'users#update_profile'
      post 'users/auth/google_oauth2', to: 'users#google_oauth2'
      post 'users/email/gmail', to: 'users#send_gmail'

      # **********Form Projection API**********
      post 'form/projection/preview', to: 'form_projection#preview'
      post 'form/projection/confirm', to: 'form_projection#confirm'

      # **********OpenAI API**********
      post 'ai/query', to: 'open_ai#query'
      post 'ai/query/documents', to: 'open_ai#query_documents'

      # ********** Generates API ***********
      post 'generates/storybook', to: 'generates#storybook'

      # **********Mini App API**********
      resources :mini_apps, only: %i[index show create update destroy] do
      end

      # **********Chatbot API**********
      resources :chatbots, only: %i[index show create update destroy] do
        member do
          get 'messages'
          post 'mark_messages_read'
        end
        collection do
          post 'assistant/message', to: 'chatbots#assistantQA'
          post 'assistant/suggestion', to: 'chatbots#assistantQASuggestion'
          post 'assistant/multiagent', to: 'chatbots#assistantMultiagent'
          post 'assistant/tool_metadata', to: 'chatbots#tool_metadata'
          post ':id/share', to: 'chatbots#shareChatbotWithSignature'
          post 'general_users/assistant/message', to: 'chatbots#general_user_chat_with_bot'
          post 'general_users/assistant/autogen/message', to: 'chatbots#general_user_chat_with_bot_via_autogen'
          get 'general_users/assistant/history', to: 'chatbots#fetch_general_user_chat_history'
          put ':id/assistive_questions', to: 'chatbots#update_assistive_questions'
        end
      end

      resources :assistant_agents, only: %i[index show]
      resources :agent_tools, only: %i[index show]

      # **********Tool API**********
      post 'tools/upload_directly_ocr', to: 'tools#upload_directly_ocr'
      post 'tools/text_to_pdf', to: 'tools#text_to_pdf'
      post 'tools/text_to_png', to: 'tools#text_to_png'
      post 'tools/upload_html_to_pdf', to: 'tools#upload_html_to_pdf'
      post 'tools/upload_html_to_png', to: 'tools#upload_html_to_png'
      post 'tools/dify_chatbot_report', to: 'tools#dify_chatbot_report'
      post 'tools/dify_prompt_wrapper', to: 'tools#dify_prompt_wrapper'
      post 'tools/export_to_notion', to: 'tools#export_to_notion'
      post 'tools/google_drive/check', to: 'tools#auth_dify_user_google_drive?'
      post 'tools/google_drive/auth', to: 'tools#auth_dify_user_google_drive'
      post 'tools/google_drive/list', to: 'tools#list_google_drive_files'
      post 'tools/google_drive/upload/document', to: 'tools#export_docx_to_google_drive'
      delete 'tools/google_drive/revoke', to: 'tools#revoke_dify_user_google_drive'

      # **********Smart Extraction Schema API**********
      resources :smart_extraction_schemas, only: %i[index show create update destroy] do
        collection do
          get ':id/data', to: 'smart_extraction_schemas#show_document_extracted_data'
          get 'label/:label_id', to: 'smart_extraction_schemas#show_by_label_id'
          post 'generate/chart', to: 'smart_extraction_schemas#generate_chart'
          post 'generate/statistics', to: 'smart_extraction_schemas#generate_statistics'
          post 'documents', to: 'smart_extraction_schemas#create_by_documents'
          post 'documents/:smart_extraction_schema_id',
               to: 'smart_extraction_schemas#push_documents_to_smart_extraction_schema'
        end
      end

      # **********Document Smart Extraction Datum API**********
      resources :document_smart_extraction_datum, only: %i[index show destroy] do
        collection do
          post ':smart_extraction_schema_id/search',
               to: 'document_smart_extraction_datum#show_by_filter_and_smart_extraction_schema_id'
          put ':id/data', to: 'document_smart_extraction_datum#update_data'
        end
      end

      # **********Project Workflow API**********
      resources :project_workflows, only: %i[index show create update destroy] do
        member do
          post 'start'
          post 'pause'
          post 'resume'
          post 'restart'
        end

        collection do
          post 'duplicate' # 複製一個 project workflow 出黎
        end
      end

      # **********Project Workflow Step API**********
      resources :project_workflow_steps, only: %i[index show create update destroy] do
        member do
          post 'start'
          post 'finish'
        end

        collection do
          get 'project_workflow/:project_workflow_id', to: 'project_workflow_steps#show_by_project_workflow_id'
        end
      end

      # ********** Dags API ***********
      resources :dags
      resources :dag_runs do
        member do
          get 'check_status_finish'
        end
      end

      # ********** Storyboard and related API ***********
      resources :storyboard_items, only: %i[index show update destroy]
      resources :storyboards, only: %i[index show create update destroy] do
        member do
          get 'storyboard_items'
        end
      end

      # ********** General User API ***********
      resources :general_users, only: %i[show create] do
        collection do
          get 'me', to: 'general_users#show_current_user'
          get 'me/purchase_history', to: 'general_users#show_purchase_history'
          get 'me/marketplace_items', to: 'general_users#show_marketplace_items'
          get 'me/marketplace_items/:id', to: 'general_users#show_marketplace_item'
          get 'me/files', to: 'general_users#show_files'
          delete 'me/files/:id', to: 'general_users#destroy_file'
          put 'me/profile', to: 'general_users#update_profile'
          put 'me/password', to: 'general_users#update_password'
          get 'me/aienglish', to: 'general_users#show_aienglish_profile'
        end
      end

      # ********** Marketplace API ***********
      resources :marketplace_items, only: %i[index show create update destroy] do
        collection do
          post 'general_users/purchase', to: 'marketplace_items#general_users_purchase'
        end
      end

      # ********** General User Feed API ***********
      resources :general_user_feeds, only: %i[index show create update destroy]

      # ********** Scheduled Task API ***********
      resources :scheduled_tasks, only: %i[index show create update destroy]
    end

    namespace :admin do
      namespace :v1 do
        resources :entities, only: %i[index show create update destroy]
        resources :users, only: %i[index show create update destroy] do
          collection do
            post 'lock', to: 'users#lock_user'
            post 'unlock', to: 'users#unlock_user'
          end
        end
        resources :general_users, only: %i[index show create update destroy] do
          collection do
            get ':id/students', to: 'general_users#show_students'
            get ':id/teachers', to: 'general_users#show_teachers'
            put ':id/password', to: 'general_users#update_password'
            put ':id/lock', to: 'general_users#lock_user'
            put ':id/unlock', to: 'general_users#unlock_user'
            post 'batch', to: 'general_users#batch_create'
            post 'student/email/batch', to: 'general_users#batch_students_relation_by_emails'
            post 'student/email', to: 'general_users#add_students_relation_by_emails'
          end
          collection do
            post 'aienglish/create', to: 'general_users#create_aienglish_user'
            post 'aienglish/batch', to: 'general_users#batch_create_aienglish_user'
            put ':id/aienglish/update', to: 'general_users#update_aienglish_user'
            put 'aienglish/batch/update', to: 'general_users#batch_update_aienglish_user'
          end
        end
        resources :schools, param: :code do
          member do
            post :assign_students
            post :assign_teachers
            post :assign_student_by_id
            post :assign_student_by_email
            post :assign_teacher_by_email
            post :assign_teacher_by_id
            get :student_stats
            get :teacher_stats
            get :academic_years
            get 'academic_years/:academic_year_id/students', to: 'schools#academic_year_students'
            get 'academic_years/:academic_year_id/classes/:class_name/students', to: 'schools#class_students'
            get 'academic_years/:academic_year_id/teachers', to: 'schools#academic_year_teachers'
            get 'academic_years/:academic_year_id/departments/:department/teachers', to: 'schools#department_teachers'
            get 'multi_year_students', to: 'schools#multi_year_students'
            put :logo, to: 'school_logos#update'
            delete :logo, to: 'school_logos#destroy'
            post :promote_students
            post :update_assignments_academic_year
          end

          collection do
            post :import_from_csv
            post :bulk_assign_students
            post :bulk_assign_teachers
            get :statistics
          end
        end
        # 學年管理
        resources :school_academic_years, only: %i[show create update destroy]
      end
    end

    # namespace :schema do
    #   namespace :v1 do
    #     # **********Chatbot API**********
    #     resources :chatbots, only: %i[index show create update destroy] do
    #       collection do
    #         post 'assistant/message', to: 'chatbots#assistantQA'
    #         post 'assistant/suggestion', to: 'chatbots#assistantQASuggestion'
    #       end
    #     end
    #   end
    # end
  end
end
