# frozen_string_literal: true

# app/models/concerns/linkable.rb
module HasKgLinker
  extend ActiveSupport::Concern

  included do
  end

  class_methods do
    def method_missing(method_name, *arguments, &block)
      puts method_name
      binding.pry if method_name.to_s == 'linked_students'
      if method_name.to_s.start_with?('linked_')
        relation_name = method_name.to_s.sub('linked_', '')

        # 调用动态处理关系的私有方法
        return linkable_relation(relation_name) if respond_to_relation?(relation_name)
      end

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      puts method_name
      binding.pry if method_name.to_s == 'linked_students'
      if method_name.to_s.start_with?('linked_')
        relation_name = method_name.to_s.sub('linked_', '')
        # if relation_name == 'students'
        #   binding.pry
        # end
        return respond_to_relation?(relation_name)
      end

      super
    end

    def linkable_relation(relation_name)
      # 查询符合条件的KgLinker记录
      # linkers = KgLinker.where(map_from: self, relation: "linked_#{relation_name}")
      linkers = KgLinker.where(map_from: self, relation: "has_#{relation_name}")

      # 根据KgLinker记录动态查找map_to对象的实例
      objects = linkers.each_with_object([]) do |linker, arr|
        # 使用constantize将map_to_type转换为对应的类，然后使用find查询实例
        map_to_class = linker.map_to_type.constantize
        arr << map_to_class.find_by(id: linker.map_to_id)
      end

      objects.compact # 移除nil元素，以防map_to_id没有找到对应的记录
    end

    def respond_to_relation?(_relation_name)
      # 假设总是返回true，或者你需要一些逻辑来验证这个关系是否有效
      true
    end
  end
end
