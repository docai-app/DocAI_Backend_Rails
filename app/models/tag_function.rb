class TagFunction < ApplicationRecord
    belongs_to :tag, optional: true, class_name: "Tag", foreign_key: "tag_id"
    belongs_to :function, optional: true, class_name: "Function", foreign_key: "function_id"
end
