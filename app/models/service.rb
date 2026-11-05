class Service < ApplicationRecord
  CRITICALITIES = %w[low medium high critical].freeze

  belongs_to :owner, class_name: "Person", optional: true

  validates :name, presence: true, uniqueness: true
  validates :criticality, inclusion: { in: CRITICALITIES }
end
