module Tools
  class GetAsset < Base
    tool "get_asset",
         description: <<~TXT,
           Get the full record for one asset: location, custodian, warranty, the open checkout (who has it and when
           it is due), maintenance tasks, and its direct dependencies and dependents. Call this when the user asks
           about a specific asset, or to confirm an asset's state before checking it out, in, or scheduling work.
         TXT
         input_schema: {
           type: "object",
           properties: {
             asset: { type: "string", minLength: 1, description: "Asset tag (e.g. AP-00042), numeric id, or exact name" }
           },
           required: ["asset"],
           additionalProperties: false
         }

    private

    def perform(input)
      asset = find_asset!(input["asset"])
      open_checkout = asset.checkouts.open.includes(:person).first
      depends_on = Dependency.where(source_type: "Asset", source_id: asset.id).map { |d| node_ref(d.target_type, d.target_id, d.kind) }
      dependents = Dependency.where(target_type: "Asset", target_id: asset.id)

      asset_brief(asset, checkout: open_checkout).merge(
        "id" => asset.id, "serial" => asset.serial, "purchased_on" => asset.purchased_on&.iso8601,
        "custodian" => person_brief(asset.custodian), "checkout" => checkout_brief(open_checkout),
        "maintenance_tasks" => asset.maintenance_tasks.order(:due_on).map do |t|
          { "id" => t.id, "kind" => t.kind, "due_on" => t.due_on.iso8601, "status" => t.status }
        end,
        "depends_on" => depends_on,
        "direct_dependents" => { "count" => dependents.count,
                                 "services" => dependents.where(source_type: "Service").count,
                                 "assets" => dependents.where(source_type: "Asset").count }
      )
    end

    def node_ref(type, id, kind)
      node = type.constantize.find_by(id: id)
      { "type" => type.downcase, "kind" => kind, "name" => node&.name }.tap { |h| h["tag"] = node.tag if node.is_a?(Asset) }
    end
  end
end
