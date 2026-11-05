class Checkout < ApplicationRecord
  belongs_to :asset
  belongs_to :person

  validates :out_at, :due_at, presence: true
  validate :due_after_out
  validate :in_after_out
  validate :asset_not_already_out, on: :create

  scope :open, -> { where(in_at: nil) }
  scope :overdue, -> { open.where(due_at: ...Time.current) }

  def open? = in_at.nil?

  private

  def due_after_out
    errors.add(:due_at, "must be after out_at") if out_at && due_at && due_at <= out_at
  end

  def in_after_out
    errors.add(:in_at, "must be after out_at") if out_at && in_at && in_at < out_at
  end

  def asset_not_already_out
    errors.add(:asset, "is already checked out") if asset && Checkout.open.where(asset_id: asset_id).exists?
  end
end
