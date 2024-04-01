# frozen_string_literal: true

# == Schema Information
#
# Table name: public.general_users
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  encrypted_password     :string
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  nickname               :string
#  phone                  :string
#  date_of_birth          :date
#  sex                    :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_general_users_on_email  (email) UNIQUE
#
require_dependency 'has_kg_linker'

class GeneralUser < ApplicationRecord
  devise :database_authenticatable,
         :jwt_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable,
         jwt_revocation_strategy: JwtDenylist

  has_one :energy, as: :user, dependent: :destroy
  has_many :purchases, as: :user, dependent: :destroy
  has_many :purchased_marketplace_items, through: :purchases, source: :marketplace_item
  has_many :user_marketplace_items, dependent: :destroy, as: :user, class_name: 'UserMarketplaceItem'
  has_many :marketplace_items, through: :user_marketplace_items
  has_many :general_user_files, dependent: :destroy
  has_many :general_user_feeds, dependent: :destroy

  # include HasKgLinker

  def jwt_payload
    {
      'sub' => id,
      'iat' => Time.now.to_i,
      'email' => email
    }
  end

  def consume_energy(marketplace_item_id, energy_cost)
    # Run the energy consumption
    if energy.value >= energy_cost
      energy.update(value: energy.value - energy_cost)
      # Create energy consumption record
      EnergyConsumptionRecord.create!(
        user: self,
        marketplace_item_id:,
        energy_consumed: energy_cost
      )
      true
    else
      false
    end
  end

  def check_can_consume_energy(_chatbot, energy_cost)
    energy.value >= energy_cost
  end

  def purchased_items
    purchases.includes(:marketplace_item).as_json(include: :marketplace_item)
  end

  # 以下方法應該是放入去 concern 的，但係唔知點解冇效，所以搬返出黎就算
  def method_missing(method_name, *arguments, &block)
    if method_name.to_s.start_with?('linked_')
      relation_name = method_name.to_s.sub('linked_', '')

      # 调用动态处理关系的私有方法
      return linkable_relation(relation_name) if respond_to_relation?(relation_name)
    end

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    if method_name.to_s.start_with?('linked_')
      relation_name = method_name.to_s.sub('linked_', '')
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
