class Asset < ApplicationRecord
  CATEGORIES = %w[laptop desktop server monitor phone tablet network printer peripheral].freeze
  STATUSES = %w[available checked_out in_maintenance retired].freeze

  belongs_to :location, optional: true
  belongs_to :custodian, class_name: "Person", optional: true
  has_many :checkouts, dependent: :destroy
  has_many :maintenance_tasks, dependent: :destroy

  validates :tag, presence: true, uniqueness: true
  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validate :warranty_after_purchase

  scope :with_status, ->(s) { where(status: s) }
  scope :in_category, ->(c) { where(category: c) }
  scope :warranty_expiring_before, ->(d) { where(warranty_until: ..d) }
  scope :search, lambda { |q|
    next all if q.blank?
    where("(coalesce(name,'') || ' ' || coalesce(tag,'') || ' ' || coalesce(serial,'')) ILIKE ?",
          "%#{sanitize_sql_like(q.to_s.strip)}%")
  }

  private

  def warranty_after_purchase
    return unless purchased_on && warranty_until && warranty_until < purchased_on
    errors.add(:warranty_until, "must be on or after purchase date")
  end
end
