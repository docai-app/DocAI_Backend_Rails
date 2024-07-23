# frozen_string_literal: true

# == Schema Information
#
# Table name: public.kg_linkers
#
#  id            :bigint(8)        not null, primary key
#  map_from_type :string           not null
#  map_to_type   :string           not null
#  meta          :jsonb            not null
#  relation      :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  map_from_id   :uuid
#  map_to_id     :uuid
#
# Indexes
#
#  index_kg_linkers_on_map_from_id  (map_from_id)
#  index_kg_linkers_on_map_to_id    (map_to_id)
#
class KgLinker < ApplicationRecord
  store_accessor :meta, :annotation
  # association macros
  belongs_to :map_from, polymorphic: true
  belongs_to :map_to, polymorphic: true

  def self.link(from, to, _user, _school)
    linker = KgLinker.new
    linker.map_from = from
    linker.map_to = to
    linker.save
  end

  def self.unlink(from, to, _user, _school)
    linker = KgLinker.where(map_from: from, map_to: to).first
    linker.destroy
  end

  def self.add_student_relation(teacher:, student:)
    linker = KgLinker.new(map_from: teacher, map_to: student)
    linker.relation = 'has_student'
    linker.save
  end
end
