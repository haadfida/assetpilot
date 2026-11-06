require "active_support/testing/time_helpers"

module Evals
  # Every eval runs inside one transaction that is always rolled back: the database is reseeded
  # (SeedData, deterministic ids), the clock frozen at AS_OF, and each case gets its own savepoint with
  # the id sequences of mutable tables reset. Mutating tools really execute; nothing survives the run.
  module Sandbox
    extend ActiveSupport::Testing::TimeHelpers

    MUTABLE_TABLES = %w[checkouts maintenance_tasks agent_runs agent_steps].freeze

    module_function

    def run
      result = nil
      travel_to(AS_OF) do
        ActiveRecord::Base.transaction(requires_new: true) do
          SeedData.run!
          result = yield
          raise ActiveRecord::Rollback
        end
      end
      result
    end

    def isolated
      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        conn = ActiveRecord::Base.connection
        MUTABLE_TABLES.each do |t|
          conn.execute("SELECT setval(pg_get_serial_sequence('#{t}', 'id'), COALESCE((SELECT MAX(id) FROM #{t}), 0) + 1, false)")
        end
        result = yield
        raise ActiveRecord::Rollback
      end
      result
    end
  end
end
