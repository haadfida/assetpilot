# Finds everything that transitively depends on a node (asset or service).
# Edges are stored as "source depends on / runs on target", so we walk from the
# target back to the sources with a recursive CTE. Cycles are cut by tracking
# the visited path per branch; recursion is bounded by max_depth.
class ImpactAnalysis
  DEFAULT_MAX_DEPTH = 10
  HARD_MAX_DEPTH = 25

  class NotFound < StandardError; end

  Result = Struct.new(:root, :max_depth, :services, :assets, :people, keyword_init: true)

  SQL = <<~SQL.freeze
    WITH RECURSIVE impact(node_type, node_id, depth, path) AS (
      SELECT d.source_type, d.source_id, 1,
             ARRAY[:root_key, d.source_type || ':' || d.source_id]
      FROM dependencies d
      WHERE d.target_type = :type AND d.target_id = :id
        AND (d.source_type || ':' || d.source_id) <> :root_key
      UNION ALL
      SELECT d.source_type, d.source_id, i.depth + 1,
             i.path || (d.source_type || ':' || d.source_id)
      FROM impact i
      JOIN dependencies d ON d.target_type = i.node_type AND d.target_id = i.node_id
      WHERE i.depth < :max_depth
        AND NOT ((d.source_type || ':' || d.source_id) = ANY (i.path))
    )
    SELECT node_type, node_id, MIN(depth) AS depth
    FROM impact
    GROUP BY node_type, node_id
    ORDER BY MIN(depth), node_type, node_id
  SQL

  def self.call(type:, id:, max_depth: DEFAULT_MAX_DEPTH)
    new(type, id, max_depth).call
  end

  def initialize(type, id, max_depth)
    @type = type.to_s.classify
    raise NotFound, "unknown node type" unless Dependency::NODE_TYPES.include?(@type)
    @root = @type.constantize.find_by(id: id) or raise NotFound, "#{@type} #{id} not found"
    @max_depth = max_depth.to_i.clamp(1, HARD_MAX_DEPTH)
  end

  def call
    rows = Dependency.connection.select_all(
      ApplicationRecord.sanitize_sql_array([SQL, { root_key: "#{@type}:#{@root.id}", type: @type,
                                                    id: @root.id, max_depth: @max_depth }])
    ).to_a
    depths = rows.to_h { |r| [[r["node_type"], r["node_id"]], r["depth"]] }

    services = Service.where(id: ids(rows, "Service")).includes(:owner).to_a
    assets = Asset.where(id: ids(rows, "Asset")).includes(:custodian).to_a
    people_ids = services.filter_map(&:owner_id) + assets.filter_map(&:custodian_id)

    Result.new(
      root: @root, max_depth: @max_depth,
      services: services.map { |s| [s, depths[["Service", s.id]]] }.sort_by { |s, d| [d, s.id] },
      assets: assets.map { |a| [a, depths[["Asset", a.id]]] }.sort_by { |a, d| [d, a.id] },
      people: Person.where(id: people_ids.uniq).order(:id).to_a
    )
  end

  private

  def ids(rows, type) = rows.select { |r| r["node_type"] == type }.map { |r| r["node_id"] }
end
