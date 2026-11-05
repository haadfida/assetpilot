module ToolHelpers
  def expect_ok(result)
    expect(result["ok"]).to be(true), -> { "expected ok, got #{result.inspect}" }
    result["data"]
  end

  def expect_error(result, code)
    expect(result["ok"]).to be(false), -> { "expected error #{code}, got #{result.inspect}" }
    expect(result.dig("error", "code")).to eq(code)
    result["error"]
  end
end

RSpec.configure { |c| c.include ToolHelpers }
