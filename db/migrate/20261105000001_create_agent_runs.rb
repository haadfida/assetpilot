class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.text :prompt, null: false
      t.string :model, null: false
      t.string :mode, null: false                      # live | replay
      t.string :status, null: false, default: "queued" # queued running succeeded failed refused max_iterations
      t.string :replay_slug                            # db/replays/<slug>.json for replay runs
      t.string :recorded                               # provenance of a replay: "synthetic"
      t.integer :iterations, null: false, default: 0   # model turns that requested tools
      t.string :stop_reason
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_input_tokens, null: false, default: 0
      t.integer :cache_creation_input_tokens, null: false, default: 0
      t.string :error_code
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.timestamps
    end
    add_index :agent_runs, :status
    add_index :agent_runs, :created_at
    add_check_constraint :agent_runs, "mode IN ('live', 'replay')", name: "agent_runs_mode_check"

    create_table :agent_steps do |t|
      t.references :agent_run, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :position, null: false
      t.string :kind, null: false # text progress tool_use tool_result error
      t.integer :iteration, null: false, default: 0
      t.text :content             # aggregated text / progress note / error message
      t.string :tool_use_id
      t.string :tool_name
      t.jsonb :input
      t.jsonb :output
      t.boolean :is_error, null: false, default: false
      t.integer :elapsed_ms       # offset from run start
      t.integer :duration_ms
      t.timestamps
    end
    add_index :agent_steps, %i[agent_run_id position], unique: true
    add_check_constraint :agent_steps, "kind IN ('text', 'progress', 'tool_use', 'tool_result', 'error')",
                         name: "agent_steps_kind_check"
  end
end
