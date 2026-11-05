RSpec.configure do |c|
  c.include ActiveSupport::Testing::TimeHelpers
  c.after { travel_back }
end
