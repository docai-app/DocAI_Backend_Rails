class Function < ApplicationRecord
    has_many :tag_functions, dependent: :destroy
    has_one :tag_function, dependent: :destroy, class_name: "TagFunction", foreign_key: "function_id"
    has_one :tag, through: :tag_functions, class_name: "Tag", foreign_key: "tag_id"
end
