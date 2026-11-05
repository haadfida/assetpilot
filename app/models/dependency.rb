# source <kind> target: the source depends on (or runs on) the target.
class Dependency < ApplicationRecord
  NODE_TYPES = %w[Asset Service].freeze
  KINDS = %w[depends_on runs_on].freeze

  validates :source_type, :target_type, inclusion: { in: NODE_TYPES }
  validates :kind, inclusion: { in: KINDS }
  validates :source_id, :target_id, presence: true
  validates :target_id, uniqueness: { scope: %i[source_type source_id target_type kind] }
  validate :not_self_referential
  validate :nodes_exist

  private

  def not_self_referential
    return unless source_type == target_type && source_id == target_id
    errors.add(:base, "a node cannot depend on itself")
  end

  def nodes_exist
    { source: [source_type, source_id], target: [target_type, target_id] }.each do |side, (type, id)|
      next unless NODE_TYPES.include?(type) && id
      errors.add(:"#{side}_id", "does not exist") unless type.constantize.exists?(id)
    end
  end
end
