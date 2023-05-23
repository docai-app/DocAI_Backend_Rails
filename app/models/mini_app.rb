class MiniApp < ApplicationRecord
    resourcify

    acts_as_taggable_on :document_labels, :app_functions

    belongs_to :user
    belongs_to :folder
end
