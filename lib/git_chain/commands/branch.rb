# frozen_string_literal: true

require "optparse"

module GitChain
  module Commands
    class Branch < Command
      def banner_options
        "<start_point> branch"
      end

      def description
        "Start a new branch, adding it to the chain"
      end

      def configure_option_parser(opts, options)
        super

        opts.on("-c", "--chain=NAME", "Chain name") do |name|
          options[:chain_name] = name
        end

        opts.on("-i", "--insert", "Insert in the middle of a chain instead of starting a new one") do
          options[:mode] = :insert
        end

        opts.on("--new", "Start a new chain instead of continuing the existing one") do
          options[:mode] = :new
        end

        opts.on("--after=BRANCH", "Insert the new branch after BRANCH in the chain") do |name|
          options[:after] = name
        end

        opts.on("--before=BRANCH", "Insert the new branch before BRANCH in the chain") do |name|
          options[:before] = name
        end
      end

      def parse_branch_options(options)
        if options[:after]
          validate_flag_exclusivity!(options)
          raise(ArgError, "Expected 1 argument (branch name)") unless options[:args].size == 1

          start_point = options[:after]
          branch_name = options[:args][0]
          raise(Abort, "#{start_point} is not a branch") if Git.exec("branch", "--list", start_point).empty?

          options[:mode] = :insert
          return [start_point, branch_name]
        end

        if options[:before]
          validate_flag_exclusivity!(options)
          raise(ArgError, "Expected 1 argument (branch name)") unless options[:args].size == 1

          # start_point resolved in run() after chain is known
          branch_name = options[:args][0]
          options[:mode] = :insert
          return [nil, branch_name]
        end

        case options[:args].size
        when 1
          start_point = Git.current_branch
          raise(Abort, "You are not currently on any branch") unless start_point

          branch_name = options[:args][0]
        when 2
          start_point, branch_name = options[:args]
        else
          raise(ArgError, "Expected 1 or 2 arguments")
        end

        raise(Abort, "#{start_point} is not a branch") if Git.exec("branch", "--list", start_point).empty?

        [start_point, branch_name]
      end

      def detect_chain(options, start_point, branch_name)
        if options[:after]
          return find_chain_for_branch(options[:after], options[:chain_name])
        end

        if options[:before]
          return find_chain_for_branch(options[:before], options[:chain_name])
        end

        return Models::Chain.from_config(options[:chain_name]) if options[:chain_name]

        return Models::Chain.from_config(branch_name) if options[:mode] == :new

        # mode is nil or :insert

        parent_branch = Models::Branch.from_config(start_point)

        return Models::Chain.from_config(branch_name) unless parent_branch.chain_name

        parent_chain = Models::Chain.from_config(parent_branch.chain_name)
        if parent_chain.branch_names.last == start_point
          parent_chain
        elsif options[:mode] == :insert
          parent_chain
        else
          # mode is nil, which will default to :new because we are in the middle of the chain
          Models::Chain.from_config(branch_name)
        end
      end

      def run(options)
        start_point, branch_name = parse_branch_options(options)

        # Validate branch doesn't already exist
        if Git.branches.include?(branch_name)
          raise(Abort, "Branch '#{branch_name}' already exists.")
        end

        chain = detect_chain(options, start_point, branch_name)
        branch_names = chain.branch_names

        # Resolve --before start_point now that chain is known
        if options[:before]
          before_index = branch_names.index(options[:before])
          raise(Abort, "Branch '#{options[:before]}' is not in chain '#{chain.name}'.") unless before_index
          raise(Abort, "Cannot insert before the base branch '#{options[:before]}'.") if before_index == 0

          start_point = branch_names[before_index - 1]
        end

        if branch_names.empty?
          raise(Abort, "Unable to insert, #{chain.name} does not exist yet") if options[:mode] == :insert

          branch_names << start_point << branch_name
        else
          is_last = branch_names.last == start_point
          mode = options[:mode] || (is_last ? :insert : :new)

          case mode
          when :insert
            if options[:after]
              index = branch_names.index(options[:after])
              raise(Abort, "Branch '#{options[:after]}' is not in chain '#{chain.name}'.") unless index

              branch_names.insert(index + 1, branch_name)
            elsif options[:before]
              before_index = branch_names.index(options[:before])
              branch_names.insert(before_index, branch_name)
            elsif is_last
              puts_info("Appending {{info:#{branch_name}}} at the end of chain {{info:#{chain.name}}}")
              branch_names << branch_name
            else
              puts_info("Inserting {{info:#{branch_name}}} after {{info:#{start_point}}} in chain #{chain.name}")
              index = branch_names.index(start_point)
              branch_names.insert(index + 1, branch_name)
            end
          when :new
            puts_info("Starting a new chain {{info:#{chain.name} from #{start_point}")
            branch_names = [start_point, branch_name]
          else
            raise("Invalid mode: #{mode}")
          end
        end

        # Check for rebase-in-progress before creating branch if middle insertion
        middle_insert = branch_names.last != branch_name
        if middle_insert && Git.rebase_in_progress?
          raise(Abort, "A rebase is in progress. Cannot insert in the middle of a chain during a rebase.")
        end

        begin
          Git.exec("checkout", "-b", branch_name, start_point)
        rescue Git::Failure => e
          raise(Abort, e)
        end

        Setup.new.call(["--chain", chain.name, *branch_names])

        # Auto-rebase downstream branches after middle insertion
        if middle_insert
          Rebase.new.call(["--chain", chain.name])
          Git.exec("checkout", branch_name)
        end
      end

      private

      def validate_flag_exclusivity!(options)
        if options[:after] && options[:before]
          raise(ArgError, "--after and --before are mutually exclusive")
        end

        if options[:mode] == :insert
          flag = options[:after] ? "--after" : "--before"
          raise(ArgError, "#{flag} cannot be combined with --insert")
        end

        if options[:mode] == :new
          flag = options[:after] ? "--after" : "--before"
          raise(ArgError, "#{flag} cannot be combined with --new")
        end
      end

      def find_chain_for_branch(target, explicit_chain_name = nil)
        # Collect all chain names from config
        all_chains = Git.chains
        chain_names = all_chains.values.uniq

        matching = []
        chain_names.each do |name|
          chain = Models::Chain.from_config(name)
          matching << chain if chain.branch_names.include?(target)
        end

        if explicit_chain_name
          chain = Models::Chain.from_config(explicit_chain_name)
          unless chain.branch_names.include?(target)
            raise(Abort, "Branch '#{target}' is not in chain '#{explicit_chain_name}'.")
          end

          return chain
        end

        if matching.empty?
          raise(Abort, "Branch '#{target}' is not in any chain.")
        end

        if matching.size > 1
          names = matching.map(&:name).join(", ")
          raise(Abort, "Branch '#{target}' belongs to multiple chains: #{names}. Use --chain to specify.")
        end

        matching.first
      end
    end
  end
end
