# Expands projects that use other projects as sub-assemblies into the parts
# they need. A BOM line can point at another project of the organization
# (ProjectLine#subproject) instead of a part, so many units of it per kit:
#
# - a sub-assembly whose project has a built item (Project#output_part) is
#   *stocked*: the parent takes that part from stock, like any other line, and
#   building the sub-assembly's project is what puts it there;
# - one without is *phantom*: the parent needs its parts directly, times the
#   line quantity, expanded through further sub-assemblies down to MAX_DEPTH.
#
# Lines are read with plucks one level at a time, so a tree costs two queries
# per level whatever its size. One instance can be shared by several projects
# of the same organization (the projects list) to read each level once.
class ProjectStructure
  # Sub-assembly levels under a top-level project. Deeper lines are refused
  # (ProjectLine validation); a tree that still goes deeper counts as incomplete.
  MAX_DEPTH = 5

  Line = Data.define(:part_id, :subproject_id, :quantity)

  # Ids of every project under +project_id+ (sub-assemblies, theirs, ...).
  def self.descendant_ids(project_id)
    walk(project_id) { |ids| ProjectLine.where(project_id: ids).where.not(subproject_id: nil).distinct.pluck(:subproject_id) }
  end

  # Ids of every project that uses +project_id+, directly or through others.
  def self.ancestor_ids(project_id)
    walk(project_id) { |ids| ProjectLine.where(subproject_id: ids).distinct.pluck(:project_id) }
  end

  # Levels of sub-assemblies under +project_id+ (0 when it uses none).
  def self.depth_below(project_id)
    levels(project_id) { |ids| ProjectLine.where(project_id: ids).where.not(subproject_id: nil).distinct.pluck(:subproject_id) }
  end

  # Levels of projects above +project_id+ (0 when no project uses it).
  def self.depth_above(project_id)
    levels(project_id) { |ids| ProjectLine.where(subproject_id: ids).distinct.pluck(:project_id) }
  end

  def initialize(organization)
    @organization = organization
    @lines = {}
    @output_parts = {}
    @depths = {}
  end

  # { part_id => quantity } one kit of top-level project +project_id+ needs:
  # its part lines plus its sub-assemblies, expanded.
  def part_quantities(project_id)
    load([ project_id ], depth: 0)
    expand(project_id, 0)
  end

  # { part_id => quantity } one unit of sub-assembly +project_id+ takes from
  # the parent's point of view: its built item when it has one, else its parts.
  def assembly_quantities(project_id)
    load([ project_id ], depth: 1)
    expand_assembly(project_id, 1)
  end

  # A sub-assembly can be built into a parent: it is stocked, or its own lines
  # are all matched (recursively) and it isn't empty or too deep.
  def complete_assembly?(project_id)
    load([ project_id ], depth: 1)
    complete?(project_id, 1)
  end

  # The built item (part id) of +project_id+, nil for a phantom sub-assembly.
  def output_part_id(project_id)
    load([ project_id ], depth: 1)
    @output_parts[project_id]
  end

  def self.walk(project_id)
    seen = Set.new
    frontier = [ project_id ]
    until frontier.empty?
      frontier = yield(frontier).reject { |id| id == project_id || seen.include?(id) }
      seen.merge(frontier)
    end
    seen
  end

  def self.levels(project_id)
    seen = Set[project_id]
    frontier = [ project_id ]
    depth = 0
    loop do
      frontier = yield(frontier).reject { |id| seen.include?(id) }
      break if frontier.empty? || depth > MAX_DEPTH * 2

      seen.merge(frontier)
      depth += 1
    end
    depth
  end
  private_class_method :walk, :levels

  private

  # Reads the lines and built items of +project_ids+ and of the projects under
  # them, level by level, down to MAX_DEPTH.
  def load(project_ids, depth:)
    frontier = project_ids.reject { |id| @lines.key?(id) && @depths[id] <= depth }
    while frontier.any? && depth <= MAX_DEPTH
      frontier.each do |id|
        @lines[id] = []
        @depths[id] = depth
      end
      ProjectLine.joins(:project).where(projects: { organization_id: @organization.id }, project_id: frontier)
        .order(:id).pluck(:project_id, :part_id, :subproject_id, :quantity)
        .each { |project_id, part_id, subproject_id, quantity| @lines[project_id] << Line.new(part_id, subproject_id, quantity) }
      @organization.projects.where(id: frontier).pluck(:id, :output_part_id).each { |id, part_id| @output_parts[id] = part_id }

      depth += 1
      frontier = @lines.values_at(*frontier).flatten.filter_map(&:subproject_id).uniq
        .reject { |id| @lines.key?(id) && @depths[id] <= depth }
    end
  end

  def expand(project_id, depth)
    totals = Hash.new(0)
    @lines.fetch(project_id, []).each do |line|
      if line.part_id
        totals[line.part_id] += line.quantity
      elsif line.subproject_id
        expand_assembly(line.subproject_id, depth + 1).each { |part_id, quantity| totals[part_id] += quantity * line.quantity }
      end
    end
    totals
  end

  def expand_assembly(project_id, depth)
    if (part_id = @output_parts[project_id])
      { part_id => 1 }
    elsif depth > MAX_DEPTH || !@lines.key?(project_id)
      {}
    else
      expand(project_id, depth)
    end
  end

  def complete?(project_id, depth)
    return true if @output_parts[project_id]
    return false if depth > MAX_DEPTH || !@lines.key?(project_id)

    lines = @lines[project_id]
    lines.any? && lines.all? do |line|
      line.part_id || (line.subproject_id && complete?(line.subproject_id, depth + 1))
    end
  end
end
