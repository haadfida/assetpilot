module Tools
  class CheckoutAsset < Base
    MAX_DAYS = 180
    DUE_HOUR = 17

    tool "checkout_asset",
         description: <<~TXT,
           Check an asset out to a person until a due date. This changes the inventory: call it only when the user
           explicitly asks to check out, lend or assign an asset to someone. Fails with a structured error if the
           asset is already checked out, retired or in maintenance, if the person is unknown or ambiguous, or if
           the due date is not between tomorrow and 180 days from today.
         TXT
         input_schema: {
           type: "object",
           properties: {
             asset: { type: "string", minLength: 1, description: "Asset tag, numeric id, or exact name" },
             person: { type: "string", minLength: 1, description: "Person email (preferred), numeric id, or name" },
             due_on: { type: "string", format: "date", description: "Return date, YYYY-MM-DD" }
           },
           required: %w[asset person due_on],
           additionalProperties: false
         }

    def self.mutating? = true

    private

    def perform(input)
      due_on = parse_date!(input["due_on"], "due_on")
      unless due_on > today && due_on <= today + MAX_DAYS
        raise Tools::Error.new("invalid_due_date", "due_on must be after today and at most #{MAX_DAYS} days out",
                               due_on: due_on.iso8601, today: today.iso8601)
      end

      asset = find_asset!(input["asset"])
      person = find_person!(input["person"])

      Asset.transaction do
        asset.lock!
        if (current = asset.checkouts.open.includes(:person).first)
          raise Tools::Error.new("already_checked_out", "#{asset.tag} is already checked out to #{current.person.name}",
                                 tag: asset.tag, checkout: checkout_brief(current))
        end
        if %w[retired in_maintenance].include?(asset.status)
          raise Tools::Error.new("asset_unavailable", "#{asset.tag} is #{asset.status.humanize(capitalize: false)}",
                                 tag: asset.tag, status: asset.status)
        end

        checkout = Checkout.create!(asset: asset, person: person, out_at: Time.current,
                                    due_at: Time.zone.local(due_on.year, due_on.month, due_on.day, DUE_HOUR))
        asset.update!(status: "checked_out")
        { checkout_id: checkout.id, asset: asset_brief(asset), person: person_brief(person),
          out_at: checkout.out_at.iso8601, due_at: checkout.due_at.iso8601 }
      end
    rescue ActiveRecord::RecordNotUnique
      raise Tools::Error.new("already_checked_out", "#{asset&.tag} was checked out concurrently", tag: asset&.tag)
    end
  end
end
