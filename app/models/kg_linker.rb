class KgLinker < ApplicationRecord
  store_accessor :meta, :annotation
  # association macros
  belongs_to :map_from, polymorphic: true
  belongs_to :map_to, polymorphic: true

  def self.link(from, to, user, school)
    linker = KgLinker.new
    linker.map_from = from
    linker.map_to = to
    linker.save
  end

  def self.unlink(from, to, user, school)
    linker = KgLinker.where(map_from: from, map_to: to).first
    linker.destroy
  end


end
