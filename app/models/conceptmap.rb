# frozen_string_literal: true

# == Schema Information
#
# Table name: conceptmaps
#
#  id           :bigint(8)        not null, primary key
#  name         :string
#  root_node    :uuid
#  status       :integer
#  introduction :string
#  meta         :jsonb            not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_conceptmaps_on_root_node  (root_node)
#  index_conceptmaps_on_root_node  (root_node)
#
class Conceptmap < ApplicationRecord
  store_accessor :meta, :cache
  enum status: { publish: 0, archive: 1 }

  after_create :create_root_node
  after_save :flush_concepts_cache!, if: :saved_change_to_name?

  def create_root_node
    return if root_node.present?

    c = Concept.new(name:)
    c['meta'] ||= {}
    c['meta']['conceptmap_id'] = id
    c.save

    self['root_node'] = c.id
    save
  end

  def update_root_node_info
    c = the_root_node
    c['meta'] ||= {}
    c['meta']['conceptmap_id'] = id
    c.save
  end

  def the_root_node
    return if root_node.nil?

    Concept.find(root_node)
  end

  def leaves
    the_root_node.nil? ? [] : the_root_node.leaves
  end

  def nodes
    the_root_node.nil? ? [] : the_root_node.nodes
  end

  def cache_stuff
    self['meta'] ||= {}
    self['meta']['cache'] ||= {}
    return if root_node.nil?

    self['meta']['cache']['concept_name_list'] = the_root_node.leaves.pluck(:name).join(',')
    self['meta']['cache']['tree_json'] = the_root_node.node_children_json
  end

  def flush_cache
    cache_stuff
    save
  end

  def find_path_for_node(tree, target_concept_id, current_path = [])
    # 檢查當前節點是否為目標節點
    if tree['meta']['concept_id'] == target_concept_id
      # 如果是，則將當前節點的 content 加入到路徑中
      current_path << { id: tree['meta']['concept_id'], name: tree['content'] }
      return current_path
    end

    # 如果當前節點不是目標節點，則遍歷子節點
    tree['children'].each do |child|
      # 將當前節點的 content 加入到路徑中
      current_path << { id: tree['meta']['concept_id'], name: tree['content'] }
      # 遞迴查找子節點
      result = find_path_for_node(child, target_concept_id, current_path)
      # 如果找到目標節點，返回完整路徑
      return result unless result.nil?

      # 如果沒有找到目標節點，則移除當前節點的 content
      current_path.pop
    end

    # 如果遍歷完整棵樹都沒有找到目標節點，則返回 nil
    nil
  end

  def find_node_by_name(name)
    n = nodes.where(name:).first
    return n if n.present?

    # 咁就睇下佢係唔係 root node
    return the_root_node if the_root_node.name == name

    nil
  end

  def remove_all_nodes
    # 呢道注意係要 order 的，要先刪子節點
    Concept.where(root_node:).order('id desc').destroy_all
  end

  def all_nodes
    [the_root_node] + nodes
  end

  def to_tree_json
    self.cache ||= {}
    if self.cache['tree_json'].nil?
      self['meta'] ||= {}
      self['meta']['cache'] ||= {}
      self['meta']['cache']['tree_json'] = the_root_node.node_children_json
      save
    end
    self.cache['tree_json']
  end

  def lookup_node(path)
    path_array = path.split(' > ')

    # look_forward
    begin
      found = _lookup_node(path_array)
      return found if found.present?
    rescue StandardError
    end

    # look_backward
    found = dfs_search(to_tree_json, path_array.reverse)
    return found if found.present?

    # 都搵唔到
    # 直接 match node name
    nodes.where(name: path_array).first
  end

  def dfs_search(node, path)
    # Check if the current node matches the first element of the path
    return node['meta']['concept_id'] if node['content'] == path[0]

    (node['children']).each do |child_node|
      concept_id = dfs_search(child_node, path)
      return concept_id if concept_id
    end

    nil
  end

  def _lookup_node(path)
    # Parse the JSON data
    # data = JSON.parse(json_data)
    data = to_tree_json

    # Navigate the JSON structure
    node = data['children'].find { |n| n['content'] == path[0] }
    path[1..].each do |content|
      node = node['children'].find { |n| n['content'] == content }
    end

    # Return the concept_id, or nil if not found
    node['meta']['concept_id'] if node
  end

  def to_markdown(url = nil)
    url = 'https://examhero.com/android/AIAdmin/admin/concept.html' if url.nil?
    generate_markdown(to_tree_json, url)
  end

  def to_markdown_no_url
    generate_markdown(to_tree_json, nil)
  end

  def generate_markdown(node, url, level = 1, prefix = '')
    markdown = ''
    content = if url.nil?
                (node['content']).to_s
              else
                "[#{node['content']}](#{url}?id=#{node['meta']['concept_id']})"
              end
    markdown += "#{prefix}- #{content}\n" # unless level == 1
    node['children'].each do |child|
      markdown += generate_markdown(child, url, level + 1, "#{prefix}  ").to_s
    end
    markdown
  end

  class Node
    attr_accessor :name, :children

    def initialize(name)
      @name = name
      @children = []
    end

    def add_child(child_node)
      @children << child_node
    end

    def to_s(level = 0)
      "#{indent(level)}#{name}\n" +
        children.map { |child| child.to_s(level + 1) }.join('')
    end

    private

    def indent(level)
      '  ' * level
    end
  end

  def self.tree_to_conceptmap(parent, children)
    return if children.empty?

    children.each do |node|
      p_node = parent.add_child(node.name)
      tree_to_conceptmap(p_node, node.children)
    end
  end

  def self.build_markdown_tree(input)
    lines = input.split("\n")
    root = nil
    stack = []

    lines[0] = lines[0].strip # 第一行要 strip
    lines.each do |line|
      next if line.blank?

      name = line.strip.sub(/^-+/, '').strip
      indent = line.match(/^\s*/)[0].size
      depth = indent / 2

      node = Node.new(name)

      # binding.pry

      if depth.zero?
        # binding.pry
        root = node
        stack.push(node)
      else
        parent = stack[depth - 1]
        parent.add_child(node)
        stack[depth] = node
      end
    end

    root
  end

  def self.from_markdown(markdown_text)
    tree = build_markdown_tree(markdown_text)
    # 開一個 conceptmap, 搵個 root node 出黎

    ctm = Conceptmap.create(name: tree.name)
    tree_to_conceptmap(ctm.the_root_node, tree.children)
    ctm
  end

  def add_child(x)
    the_root_node.add_child(x)
  end
end
