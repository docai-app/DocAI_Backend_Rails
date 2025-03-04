# frozen_string_literal: true

# == Schema Information
#
# Table name: concepts
#
#  id         :bigint(8)        not null, primary key
#  source     :string
#  name       :string
#  root_node  :uuid
#  meta       :jsonb            not null
#  sort       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_concepts_on_root_node  (root_node)
#
class Concept < ApplicationRecord
  store_accessor :meta, :conceptmap_name, :conceptmap_id, :introduction
  acts_as_tree order: :sort

  before_save :strip_name
  before_destroy :remove_user_concepts

  def strip_name
    self['name'] = self['name'].strip
  end

  def meta
    self['meta'] || {}
  end

  def flush_conceptmap_data(ctm)
    self['meta'] ||= {}
    self['meta']['conceptmap_name'] = ctm.name
    self['meta']['conceptmap_id'] = ctm.id
    # binding.pry
    save
  end

  def to_label
    name
  end

  def conceptmap
    return Conceptmap.find(conceptmap_id) if conceptmap_id.present?

    Conceptmap.where(root_node:).first
  end

  def all_parents
    res = []
    next_parent = parent
    while next_parent.present?
      res << next_parent
      next_parent = next_parent.parent
    end
    res
  end

  def descendants
    res = []
    children.each do |child|
      res << if child.children.empty?
               child
             else
               child.descendants
             end
    end
    res
  end

  def add_child(child_name)
    rnid = root_node || id
    children.create(name: child_name, school_id:, source:, major:, root_node: rnid)
  end

  def node_children_json
    if children.count.zero?
      { 'meta': { 'concept_id': id, 'key_point': key_point }, 'content': name, 'children': [] }
    else
      { 'meta': { 'concept_id': id, 'key_point': key_point }, 'content': name,
        'children': children.map(&:node_children_json) }
    end
  end

  # root node should call only
  def reset_children_root_node(root_id = nil)
    root_id = id if root_id.nil?
    children.each do |child|
      child.update(root_node: root_id)
      child.reset_children_root_node(root_id)
    end
  end

  # 雖然叫 leaves, 其實係搵 key_point
  # 如果冇 set 過 key_point, 就真係 leaves
  def leaves
    concepts = Concept.where(root_node: id).where(key_point: true)
    concepts = Concept.leaves.where(root_node: id) if concepts.empty?
    concepts
  end

  def nodes
    Concept.where(root_node: id)
  end

  def linked_concepts
    ids = KgLinker.where(map_from: self, map_to_type: 'Concept').pluck(:map_to_id)
    Concept.where(id: ids)
  end

  def self.clear_deleted_linker
    concept_ids = KgLinker.where(map_from_type: 'Concept').pluck(:map_from_id)
    exist_ids = Concept.where(id: concept_ids).pluck(:id)
    can_delete_ids = concept_ids - exist_ids
    # binding.pry
    KgLinker.where(map_from_type: 'Concept', map_from_id: can_delete_ids).destroy_all
  end
end
