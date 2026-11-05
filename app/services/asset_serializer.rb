class AssetSerializer
  def self.call(a)
    a.slice(:id, :tag, :name, :category, :status, :serial, :purchased_on, :warranty_until,
            :location_id, :custodian_id).merge(location: a.location&.name, custodian: a.custodian&.name)
  end
end
