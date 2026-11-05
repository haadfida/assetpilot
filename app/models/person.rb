class Person < ApplicationRecord
  self.table_name = "people"
  has_many :custodied_assets, class_name: "Asset", foreign_key: :custodian_id, inverse_of: :custodian, dependent: :nullify
  has_many :owned_services, class_name: "Service", foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify
  has_many :checkouts, dependent: :restrict_with_error

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
end
