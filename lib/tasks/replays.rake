namespace :replays do
  desc "Rebuild db/replays/*.json by running each scenario's tools for real (in a rolled-back, reseeded transaction)"
  task build: :environment do
    Replays::Builder.new.build_all.each do |f|
      tools = f["steps"].select { |s| s["type"] == "tool_use" }.map { |s| s["name"] }
      puts format("%-28s %-70s tools: %s", f["slug"], f["prompt"].inspect, tools.join(", "))
    end
  end

  desc "Re-check db/replays/*.json: re-run every recorded tool call and rebuild each scenario"
  task verify: :environment do
    problems = Replays::Builder.new.verify_all
    if problems.empty?
      puts "#{Replays::Scenarios::ALL.size} replays verified against the seeded database."
    else
      puts problems
      abort "replays:verify failed"
    end
  end
end
