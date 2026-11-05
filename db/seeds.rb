# Deterministic synthetic data; see lib/seed_data.rb. Re-running wipes and rebuilds the tables.
return if Rails.env.test? # specs build their own data (spec/replays uses SeedData.run! directly)

SeedData.run!
puts SeedData.summary
