# frozen_string_literal: true

require "parser"

module ProjectFixtures
  TRACKER = Hash.new { false }

  class Autocorrector < Parser::TreeRewriter
    attr_reader :filename, :nodes, :buffer

    def initialize(filename, nodes, project_name, start_loc)
      @filename = filename
      @project_name = project_name
      @start_loc = start_loc
      @nodes = nodes
      @buffer = Parser::Source::Buffer.new("(#{filename})")
      buffer.source = File.read(filename)

      super()
    end

    def correct
      File.open(filename, "w") do |file|
        file.write(rewrite(buffer, Parser::CurrentRuby.new.parse(buffer)))
      end
    end

    def on_block(node)
      target_node = nodes.any? do |offense_node|
        node == offense_node && node.loc.line == offense_node.loc.line &&
          # TODO: Why are we sent nodes that are not tracked?
          Finder::TRACKED_LETS.include?(let_name(node))
      end

      return super unless target_node || TRACKER[node]

      let_name = let_name(node)
      if Finder::FILE_NAMES.include?(let_name)
        replace(
          block_range(node),
          "let(:#{let_name}) { project_dependency_files(\"#{@project_name}\") }"
        )
      else
        remove(block_range(node))
      end

      TRACKER[node] = true

      super
    end

    private

    def let_name(node)
      send, = *node
      _, _, name = *send
      name.children.last
    end

    def block_range(node)
      Parser::Source::Range.new(
        buffer,
        node.loc.expression.begin_pos,
        node.loc.expression.end_pos
      )
    end
  end
end
