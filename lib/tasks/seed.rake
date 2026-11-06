namespace :db do
  desc "Seed the deterministic demo data only when the database has no assets (safe to run on every boot)"
  task seed_if_empty: :environment do
    if Asset.exists?
      puts "Database already has #{Asset.count} assets; not reseeding."
    else
      SeedData.run!
      puts SeedData.summary
    end
  end
end
