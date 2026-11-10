module Replays
  # The recorded prompts. Each script calls the real tools through a Session and composes the assistant's
  # text from a template over the actual tool outputs, so every tag, name and count in a replay is true for
  # the seeded database at Builder::AS_OF. `rake replays:build` writes db/replays/<slug>.json.
  module Scenarios
    Scenario = Struct.new(:slug, :prompt, :aliases, :script, keyword_init: true)

    module Text
      module_function

      def more(total, shown) = total > shown ? " (and #{total - shown} more)" : ""

      def bullets(items) = items.map { |i| "- #{i}" }.join("\n")

      def plural(n, word) = "#{n} #{n == 1 ? word : word.pluralize}"

      def date(iso) = Date.iso8601(iso).strftime("%-d %b %Y")
    end

    T = Text

    ALL = [
      Scenario.new(
        slug: "db-server-outage",
        prompt: "What breaks if DB-Server goes down?",
        aliases: ["What happens if DB-Server fails?", "Impact of DB-Server going down"],
        script: lambda do |s|
          r = s.turn("I'll trace everything that depends on DB-Server through the dependency graph.") do |t|
            t.call("impact_analysis", node_type: "asset", node: "DB-Server")
          end
          c = r["counts"]
          direct = r["services"].select { |x| x["depth"] == 1 }
          high = r["services"].select { |x| %w[critical high].include?(x["criticality"]) }
          owners = r["services"].first(6).map { |x| "#{x['name']}: #{x['owner'] || 'no owner'}" }
          s.answer(<<~MD.strip)
            If **DB-Server (#{r.dig('root', 'tag')})** goes down, the outage reaches **#{T.plural(c['services'], 'service')}**, **#{T.plural(c['assets'], 'asset')}** and **#{T.plural(c['people'], 'person')}** to notify.

            **Directly hit** (they run on DB-Server): #{direct.map { |x| "#{x['name']} (#{x['criticality']})" }.to_sentence}.

            **Knock-on effects**: #{(r['services'] - direct).first(6).map { |x| "#{x['name']} (#{x['depth']} hops)" }.to_sentence}#{T.more(c['services'] - direct.size, [(r['services'] - direct).size, 6].min)}. #{T.plural(high.size, 'affected service')} #{high.size == 1 ? 'is' : 'are'} rated high or critical.

            **Assets affected**: #{r['assets_by_category'].map { |cat, n| "#{n} #{cat.pluralize(n)}" }.to_sentence}, starting with #{r['assets'].first(3).map { |a| "#{a['tag']} #{a['name']}" }.to_sentence}.

            **Service owners to call first**:
            #{T.bullets(owners)}
          MD
        end
      ),

      Scenario.new(
        slug: "overdue-laptops",
        prompt: "Which laptops are overdue and who has them?",
        aliases: ["Show overdue laptops", "Which laptops are overdue?"],
        script: lambda do |s|
          r = s.turn("Let me look up laptops with overdue checkouts.") do |t|
            t.call("search_assets", category: "laptop", overdue: true, limit: 50)
          end
          rows = r["assets"].map do |a|
            co = a["checkout"]
            "| #{a['tag']} | #{a['name']} | #{co['person']} | #{T.date(co['due_at'])} | #{co['days_overdue']} |"
          end
          people = r["assets"].map { |a| a.dig("checkout", "person") }.uniq
          worst = r["assets"].first
          s.answer(<<~MD.strip)
            **#{T.plural(r['total'], 'laptop')}** #{r['total'] == 1 ? 'is' : 'are'} overdue, held by #{T.plural(people.size, 'person')}. The oldest is #{worst['tag']} (#{worst['name']}), with #{worst.dig('checkout', 'person')} for #{worst.dig('checkout', 'days_overdue')} days past due.

            | Tag | Laptop | Checked out to | Due | Days overdue |
            | --- | --- | --- | --- | --- |
            #{rows.join("\n")}

            I can check any of these in once they are returned, or list each person's email for a reminder.
          MD
        end
      ),

      Scenario.new(
        slug: "checkin-ap-00014",
        prompt: "Check in asset AP-00014",
        aliases: ["Check in AP-00014", "Return AP-00014"],
        script: lambda do |s|
          r = s.turn("Checking in AP-00014.") { |t| t.call("checkin_asset", asset: "AP-00014") }
          late = r["returned_late"] ? " It came back **#{r['days_overdue']} days late** (it was due #{T.date(r['was_due_at'])})." : ""
          s.answer(<<~MD.strip)
            Done: **#{r.dig('asset', 'tag')} #{r.dig('asset', 'name')}** is checked in from #{r.dig('returned_by', 'name')} and is now **#{r.dig('asset', 'status')}**.#{late}

            Its warranty #{r.dig('asset', 'warranty_expired') ? "expired on #{T.date(r.dig('asset', 'warranty_until'))}" : "runs until #{T.date(r.dig('asset', 'warranty_until'))}"}, so #{r.dig('asset', 'warranty_expired') ? 'consider an inspection before lending it out again' : 'it can go straight back into the pool'}.
          MD
        end
      ),

      Scenario.new(
        slug: "dc1-warranty-maintenance",
        prompt: "Schedule an inspection for every server in Data-Center-1 whose warranty has expired, due 2026-11-12.",
        aliases: ["Schedule inspections due 2026-11-12 for out-of-warranty servers in Data-Center-1"],
        script: lambda do |s|
          found = s.turn("First I'll find the Data-Center-1 servers whose warranty has expired.") do |t|
            t.call("search_assets", location: "Data-Center-1", category: "server", warranty: "expired", limit: 50)
          end
          due = "2026-11-12" # the date the prompt gives; one week after Builder::AS_OF
          tags = found["assets"].map { |a| a["tag"] }
          r = s.turn("Scheduling an inspection for each of the #{tags.size} servers, due #{due}.") do |t|
            t.call("schedule_maintenance", assets: tags, kind: "inspection", due_on: due)
          end
          lines = found["assets"].map { |a| "#{a['tag']} #{a['name']} (warranty ended #{T.date(a['warranty_until'])})" }
          skipped = r["skipped"].any? ? "\n\nSkipped: #{r['skipped'].map { |x| "#{x['tag']} (#{x['reason'].humanize(capitalize: false)})" }.to_sentence}." : ""
          s.answer(<<~MD.strip)
            I scheduled **#{T.plural(r['scheduled_count'], 'inspection')}** in Data-Center-1, all due **#{T.date(r['due_on'])}**:

            #{T.bullets(lines)}#{skipped}
          MD
        end
      ),

      Scenario.new(
        slug: "fleet-summary",
        prompt: "Summarize the fleet",
        aliases: ["Give me a fleet overview", "Fleet summary", "How healthy is our inventory?"],
        script: lambda do |s|
          r = s.turn("Pulling the fleet-wide numbers.") { |t| t.call("summarize_fleet") }
          cats = r["by_category"].first(4).map { |c, n| "#{n} #{c.pluralize(n)}" }
          locs = r["by_location"].first(3).map { |l, n| "#{l} (#{n})" }
          s.answer(<<~MD.strip)
            **#{r['total_assets']} assets** across #{T.plural(r['by_location'].size, 'location')}, as of #{T.date(r['as_of'])}.

            - **Status**: #{r['by_status'].map { |st, n| "#{n} #{st.humanize(capitalize: false)}" }.to_sentence}.
            - **Mix**: mostly #{cats.to_sentence}#{T.more(r['by_category'].size, 4).sub('more', 'more categories')}.
            - **Biggest sites**: #{locs.to_sentence}.
            - **Warranty**: #{r.dig('warranty', 'expired')} assets are out of warranty and #{r.dig('warranty', 'expiring_within_90_days')} more expire within 90 days.
            - **Checkouts**: #{r.dig('checkouts', 'open')} open, **#{r.dig('checkouts', 'overdue')} overdue**.
            - **Maintenance**: #{r.dig('maintenance', 'scheduled')} scheduled and #{r.dig('maintenance', 'in_progress')} in progress; **#{r.dig('maintenance', 'overdue')} are past their due date**.
            - **Services**: #{r['services_by_criticality'].sum { |_, n| n }} in total (#{r['services_by_criticality'].map { |c, n| "#{n} #{c}" }.join(', ')}).

            The two things to act on are the overdue checkouts and the overdue maintenance backlog.
          MD
        end
      ),

      Scenario.new(
        slug: "checkout-macbook",
        prompt: "Check out an available MacBook Pro to Shannon Kuhn for two weeks",
        aliases: ["Lend Shannon Kuhn a MacBook Pro for two weeks"],
        script: lambda do |s|
          found = s.turn("Looking for an available MacBook Pro.") do |t|
            t.call("search_assets", query: "MacBook Pro", status: "available", limit: 5)
          end
          pick = found["assets"].first
          due = (Date.iso8601(found["as_of"]) + 14).iso8601
          r = s.turn("#{pick['tag']} is free; checking it out to Shannon Kuhn until #{due}.") do |t|
            t.call("checkout_asset", asset: pick["tag"], person: "Shannon Kuhn", due_on: due)
          end
          s.answer(<<~MD.strip)
            Checked out **#{r.dig('asset', 'tag')} #{r.dig('asset', 'name')}** to **#{r.dig('person', 'name')}** (#{r.dig('person', 'email')}), due back **#{T.date(r['due_at'])}**.

            It was one of #{T.plural(found['total'], 'available MacBook Pro')}; I picked the first by tag, located at #{pick['location']}. #{pick['warranty_expired'] ? "Note that its warranty expired on #{T.date(pick['warranty_until'])}." : ''}
          MD
        end
      ),

      Scenario.new(
        slug: "checkout-conflict-ap-00016",
        prompt: "Check out AP-00016 to Marguerite Little",
        aliases: ["Assign AP-00016 to Marguerite Little"],
        script: lambda do |s|
          err = s.turn("Checking out AP-00016 to Marguerite Little.") do |t|
            t.call("checkout_asset", asset: "AP-00016", person: "Marguerite Little",
                                     due_on: (Time.zone.today + 14).iso8601)
          end
          held = err.dig("error", "details", "checkout")
          alts = s.turn("AP-00016 is still out, so I'll look for an available ThinkPad T14 instead.") do |t|
            t.call("search_assets", query: "ThinkPad T14", status: "available", limit: 3)
          end
          s.answer(<<~MD.strip)
            I couldn't check out **AP-00016**: it is still checked out to **#{held['person']}** and was due back #{T.date(held['due_at'])}, #{held['days_overdue']} days ago. Nothing was changed.

            Available alternatives of the same model (#{T.plural(alts['total'], 'ThinkPad T14')} free in total):
            #{T.bullets(alts['assets'].map { |a| "#{a['tag']} #{a['name']}, at #{a['location']}" })}

            Should I check one of these out to Marguerite Little instead, or check AP-00016 in first?
          MD
        end
      ),

      Scenario.new(
        slug: "email-gateway-outage",
        prompt: "What happens if the Email Gateway goes down?",
        aliases: ["What breaks if the Email Gateway fails?", "Email Gateway outage impact"],
        script: lambda do |s|
          r = s.turn("Running an impact analysis on the Email Gateway service.") do |t|
            t.call("impact_analysis", node_type: "service", node: "Email Gateway")
          end
          c = r["counts"]
          svcs = r["services"].map { |x| "#{x['name']} (#{x['criticality']}, #{x['depth']} hop#{'s' unless x['depth'] == 1}, owner #{x['owner'] || 'none'})" }
          s.answer(<<~MD.strip)
            An Email Gateway outage (#{r.dig('root', 'criticality')} criticality) would affect **#{T.plural(c['services'], 'service')}**, **#{T.plural(c['assets'], 'asset')}** and **#{T.plural(c['people'], 'person')}**.

            #{c['services'].zero? ? 'No other service depends on it.' : "Dependent services:\n#{T.bullets(svcs.first(8))}#{T.more(c['services'], [svcs.size, 8].min)}"}

            #{c['assets'].zero? ? 'No assets depend on it directly or indirectly.' : "Affected assets are mostly #{r['assets_by_category'].sort_by { |_, n| -n }.first(3).map { |cat, n| "#{cat.pluralize(n)} (#{n})" }.to_sentence}, e.g. #{r['assets'].first(3).map { |a| "#{a['tag']} (#{a['custodian'] || 'no custodian'})" }.to_sentence}."}
          MD
        end
      )
    ].freeze
  end
end
