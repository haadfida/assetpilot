FactoryBot.define do
  factory :location do
    sequence(:name) { |n| "Site #{n}" }
  end

  factory :person do
    sequence(:name) { |n| "Person #{n}" }
    sequence(:email) { |n| "person#{n}@example.test" }
    department { "IT" }
  end

  factory :asset do
    sequence(:tag) { |n| format("T-%04d", n) }
    sequence(:name) { |n| "Asset #{n}" }
    category { "laptop" }
    status { "available" }
    sequence(:serial) { |n| "SER#{n}" }
  end

  factory :service do
    sequence(:name) { |n| "Service #{n}" }
    criticality { "medium" }
  end

  factory :dependency do
    kind { "depends_on" }
    transient do
      source { nil }
      target { nil }
    end
    after(:build) do |d, e|
      if e.source
        d.source_type = e.source.class.name
        d.source_id = e.source.id
      end
      if e.target
        d.target_type = e.target.class.name
        d.target_id = e.target.id
      end
    end
  end

  factory :checkout do
    asset
    person
    out_at { Time.zone.parse("2026-01-01 09:00") }
    due_at { Time.zone.parse("2026-01-15 09:00") }
  end

  factory :maintenance_task do
    asset
    due_on { Date.new(2026, 3, 1) }
    kind { "inspection" }
  end
end
