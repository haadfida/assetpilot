class MaintenanceTask < ApplicationRecord
  KINDS = %w[inspection repair firmware_update cleaning battery_replacement].freeze
  STATUSES = %w[scheduled in_progress done cancelled].freeze

  belongs_to :asset

  validates :due_on, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :upcoming, -> { where(status: "scheduled").order(:due_on) }
end
