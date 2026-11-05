module Tools
  class CheckinAsset < Base
    tool "checkin_asset",
         description: <<~TXT,
           Check a checked-out asset back in, closing its open checkout and marking it available. This changes the
           inventory: call it only when the user asks to check in or return an asset. Fails with a structured
           error if the asset is unknown or has no open checkout. Reports whether the return was overdue.
         TXT
         input_schema: {
           type: "object",
           properties: {
             asset: { type: "string", minLength: 1, description: "Asset tag, numeric id, or exact name" }
           },
           required: ["asset"],
           additionalProperties: false
         }

    def self.mutating? = true

    private

    def perform(input)
      asset = find_asset!(input["asset"])

      Asset.transaction do
        asset.lock!
        checkout = asset.checkouts.open.includes(:person).first
        unless checkout
          raise Tools::Error.new("not_checked_out", "#{asset.tag} has no open checkout", tag: asset.tag, status: asset.status)
        end

        was = checkout_brief(checkout)
        checkout.update!(in_at: Time.current)
        asset.update!(status: "available") if asset.status == "checked_out"
        { checkout_id: checkout.id, asset: asset_brief(asset), returned_by: person_brief(checkout.person),
          checked_in_at: checkout.in_at.iso8601, was_due_at: was["due_at"],
          returned_late: was["overdue"], days_overdue: was["days_overdue"] }
      end
    end
  end
end
