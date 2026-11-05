class CreateDomain < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :locations do |t|
      t.string :name, null: false
      t.string :city
      t.timestamps
    end
    add_index :locations, :name, unique: true

    create_table :people do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :department
      t.timestamps
    end
    add_index :people, "lower(email)", unique: true, name: "index_people_on_lower_email"
    add_index :people, :department

    create_table :assets do |t|
      t.string :tag, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.string :status, null: false, default: "available"
      t.string :serial
      t.date :purchased_on
      t.date :warranty_until
      t.references :location, foreign_key: true
      t.references :custodian, foreign_key: { to_table: :people }
      t.timestamps
    end
    add_index :assets, :tag, unique: true
    add_index :assets, :category
    add_index :assets, :status
    add_index :assets, :serial
    add_index :assets, :warranty_until
    add_index :assets, "(coalesce(name,'') || ' ' || coalesce(tag,'') || ' ' || coalesce(serial,'')) gin_trgm_ops",
              using: :gin, name: "index_assets_on_search_text"

    create_table :services do |t|
      t.string :name, null: false
      t.string :criticality, null: false, default: "medium"
      t.references :owner, foreign_key: { to_table: :people }
      t.timestamps
    end
    add_index :services, :name, unique: true
    add_index :services, :criticality

    # A row reads: source <kind> target, i.e. "source depends on / runs on target".
    # If the target fails, the source is impacted.
    create_table :dependencies do |t|
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :kind, null: false, default: "depends_on"
      t.timestamps
    end
    add_index :dependencies, %i[source_type source_id target_type target_id kind],
              unique: true, name: "index_dependencies_uniqueness"
    add_index :dependencies, %i[target_type target_id], name: "index_dependencies_on_target"
    add_check_constraint :dependencies, "source_type IN ('Asset','Service') AND target_type IN ('Asset','Service')",
                         name: "dependencies_types_check"

    create_table :checkouts do |t|
      t.references :asset, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.datetime :out_at, null: false
      t.datetime :due_at, null: false
      t.datetime :in_at
      t.timestamps
    end
    add_index :checkouts, :asset_id, unique: true, where: "in_at IS NULL", name: "index_checkouts_one_open_per_asset"
    add_index :checkouts, :due_at, where: "in_at IS NULL", name: "index_checkouts_open_due"

    create_table :maintenance_tasks do |t|
      t.references :asset, null: false, foreign_key: true
      t.date :due_on, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "scheduled"
      t.timestamps
    end
    add_index :maintenance_tasks, %i[status due_on]
  end
end
