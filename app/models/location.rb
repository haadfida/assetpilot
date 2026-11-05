class Location < ApplicationRecord
  has_many :assets, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: true
end
