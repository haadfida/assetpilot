module Evals
  # Resolves a case's `refs` with the same lookups the tools use, so "exists" means a tool given that
  # reference finds exactly one record, "ambiguous" that it would ask which one, and "missing" not_found.
  class RefResolver < Tools::Base
    def state(kind, ref)
      case kind
      when "assets" then find_asset!(ref)
      when "people" then find_person!(ref)
      when "services" then find_service!(ref)
      when "locations"
        n = Location.where("name ILIKE ?", "%#{Location.sanitize_sql_like(ref)}%").count
        return { 0 => "missing", 1 => "exists" }.fetch(n, "ambiguous")
      end
      "exists"
    rescue Tools::Error => e
      { "not_found" => "missing", "ambiguous" => "ambiguous" }.fetch(e.code, e.code)
    end
  end
end
