# Deterministic synthetic data, shared by db/seeds.rb and the replay specs.
# Re-running wipes and rebuilds the domain tables; ids restart at 1, so ids are deterministic too
# (the replay fixtures in db/replays and `rake replays:verify` rely on that).
require "faker"

module SeedData
  BASE = Time.utc(2026, 1, 15, 9)
  TABLES = %w[maintenance_tasks checkouts dependencies assets services people locations].freeze

  module_function

  def run!
    Faker::Config.random = Random.new(42)
    rng = Random.new(42)

    ActiveRecord::Base.transaction do
      # TRUNCATE ... RESTART IDENTITY is transactional in Postgres (rolled back with the transaction).
      ActiveRecord::Base.connection.execute("TRUNCATE #{TABLES.join(', ')} RESTART IDENTITY CASCADE")

      locations = Array.new(8) do |i|
        Location.create!(name: "#{Faker::Address.city} #{%w[HQ Campus Depot Lab Annex DC Office Warehouse][i]}", city: Faker::Address.city)
      end

      departments = %w[Engineering IT Finance Sales Support HR Operations Design]
      people = Array.new(60) do |i|
        name = Faker::Name.name
        Person.create!(name: name, email: "#{name.parameterize(separator: '.')}.#{i}@example.test", department: departments[rng.rand(departments.size)])
      end

      catalog = {
        "laptop" => ["Latitude 7440", "ThinkPad T14", "MacBook Pro 14"], "desktop" => ["OptiPlex 7010", "iMac 24"],
        "server" => ["PowerEdge R650", "ProLiant DL380"], "monitor" => ["UltraSharp U2723", "Studio Display"],
        "phone" => ["iPhone 15", "Pixel 8"], "tablet" => ["iPad Air", "Galaxy Tab S9"],
        "network" => ["Catalyst 9300", "UniFi Switch 48", "FortiGate 100F"], "printer" => ["LaserJet M507", "EcoTank L6270"],
        "peripheral" => ["Docking Station", "Webcam C920"]
      }
      weights = { "laptop" => 170, "desktop" => 60, "server" => 40, "monitor" => 90, "phone" => 50,
                  "tablet" => 20, "network" => 30, "printer" => 15, "peripheral" => 25 }
      categories = weights.flat_map { |c, n| [c] * n }.shuffle(random: rng)

      assets = categories.each_with_index.map do |cat, i|
        purchased = Date.new(2020, 1, 1) + rng.rand(0..2000)
        Asset.create!(
          tag: format("AP-%05d", i + 1), name: "#{Faker::Company.name.split.first} #{catalog[cat].sample(random: rng)}",
          category: cat, status: "available", serial: Faker::Alphanumeric.alphanumeric(number: 10).upcase,
          purchased_on: purchased, warranty_until: purchased + [365, 730, 1095].sample(random: rng),
          location: locations.sample(random: rng), custodian: (rng.rand < 0.6 ? people.sample(random: rng) : nil)
        )
      end

      service_names = ["Customer Portal", "Billing API", "Internal Wiki", "Email Gateway", "Payroll", "CRM", "Data Warehouse",
                       "Identity Provider", "VPN", "CI/CD Pipeline", "Monitoring", "Backup Service"]
      crit = %w[critical high high medium medium medium low]
      services = service_names.map do |n|
        Service.create!(name: n, criticality: crit.sample(random: rng), owner: people.sample(random: rng))
      end

      infra = assets.select { |a| %w[server network].include?(a.category) }
      edges = Set.new
      add = lambda do |s, t, kind|
        next if s == t
        edges << [s.class.name, s.id, t.class.name, t.id, kind]
      end

      # Services run on servers (each on 1-3).
      services.each { |s| infra.sample(rng.rand(1..3), random: rng).each { |a| add.(s, a, "runs_on") } }
      # Services depend on earlier-listed services (keeps this layer acyclic).
      services.each_with_index { |s, i| services[0...i].sample([i, 2].min, random: rng).each { |t| add.(s, t, "depends_on") } if i.positive? }
      # Servers depend on network gear.
      net = assets.select { |a| a.category == "network" }
      assets.select { |a| a.category == "server" }.each { |a| add.(a, net.sample(random: rng), "depends_on") }
      # Remaining edges: end-user kit depends on network/infra assets or services, until ~200.
      endpoints = assets.reject { |a| %w[server network].include?(a.category) }
      while edges.size < 200
        src = endpoints.sample(random: rng)
        tgt = rng.rand < 0.5 ? infra.sample(random: rng) : services.sample(random: rng)
        add.(src, tgt, "depends_on")
      end
      Dependency.insert_all(edges.map { |st, si, tt, ti, k| { source_type: st, source_id: si, target_type: tt, target_id: ti, kind: k, created_at: BASE, updated_at: BASE } })

      # A few open checkouts, history and maintenance.
      portable = assets.select { |a| %w[laptop tablet phone].include?(a.category) }.first(40)
      portable.first(25).each_with_index do |a, i|
        out = BASE + i.days
        Checkout.create!(asset: a, person: people.sample(random: rng), out_at: out, due_at: out + 14.days, in_at: i < 10 ? out + 7.days : nil)
        a.update!(status: "checked_out") if i >= 10
      end
      assets.sample(30, random: rng).each_with_index do |a, i|
        MaintenanceTask.create!(asset: a, due_on: Date.new(2026, 2, 1) + i * 3, kind: MaintenanceTask::KINDS.sample(random: rng),
                                status: MaintenanceTask::STATUSES.first(2).sample(random: rng))
      end

      named_infrastructure!(people, services)
    end
  end

  # Hand-named Data-Center-1 kit, added after the random data so the Random(42) stream above is
  # untouched. The agent replays ("What breaks if DB-Server goes down?", ...) refer to it. No rng here.
  def named_infrastructure!(people, services)
    dc1 = Location.create!(name: "Data-Center-1", city: "Frankfurt")
    node = lambda do |tag, name, cat, purchased, warranty, custodian = nil|
      Asset.create!(tag: tag, name: name, category: cat, status: "available", serial: "DC1#{tag.delete('-')}",
                    purchased_on: purchased, warranty_until: warranty, location: dc1, custodian: custodian)
    end
    switch = node.("AP-00501", "Core-Switch-DC1", "network", Date.new(2022, 3, 1), Date.new(2027, 3, 1))
    db = node.("AP-00502", "DB-Server", "server", Date.new(2021, 6, 1), Date.new(2024, 6, 1), people[0])
    app1 = node.("AP-00503", "App-Server-01", "server", Date.new(2022, 9, 1), Date.new(2025, 9, 1), people[1])
    app2 = node.("AP-00504", "App-Server-02", "server", Date.new(2024, 2, 1), Date.new(2027, 2, 1), people[1])
    nas = node.("AP-00505", "Backup-NAS", "server", Date.new(2021, 11, 1), Date.new(2026, 5, 31))
    pdu = node.("AP-00506", "Rack-PDU-A", "peripheral", Date.new(2023, 1, 10), Date.new(2026, 12, 15))

    svc = services.index_by(&:name)
    [
      [db, switch, "depends_on"], [app1, switch, "depends_on"], [app2, switch, "depends_on"],
      [nas, switch, "depends_on"], [switch, pdu, "depends_on"], [app1, db, "depends_on"], [app2, db, "depends_on"],
      [svc.fetch("Data Warehouse"), db, "runs_on"], [svc.fetch("Billing API"), db, "runs_on"],
      [svc.fetch("Payroll"), db, "runs_on"], [svc.fetch("Customer Portal"), app1, "runs_on"],
      [svc.fetch("Backup Service"), nas, "runs_on"]
    ].each do |s, t, kind|
      Dependency.find_or_create_by!(source_type: s.class.name, source_id: s.id, target_type: t.class.name,
                                    target_id: t.id, kind: kind)
    end
  end

  def summary
    "Seeded: #{Asset.count} assets, #{Person.count} people, #{Location.count} locations, " \
      "#{Service.count} services, #{Dependency.count} dependencies, #{Checkout.count} checkouts, " \
      "#{MaintenanceTask.count} maintenance tasks"
  end
end
