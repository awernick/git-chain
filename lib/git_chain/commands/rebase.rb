# frozen_string_literal: true

require "optparse"

module GitChain
  module Commands
    class Rebase < Command
      include Options::ChainName

      def description
        "Rebase all branches of the chain"
      end

      def run(options)
        if Git.rebase_in_progress?
          raise(Abort, "A rebase is in progress. Please finish the rebase first and run 'git chain rebase' after.")
        end

        chain = current_chain(options)

        puts_debug("Rebasing chain #{chain.formatted}}}")

        branches_to_rebase = chain.branches[1..-1]

        raise(Abort, "No branches to rebase for chain '#{chain.name}'.") if branches_to_rebase.empty?

        result = ChainRebase.call(chain, auto_forward: true) do |event, *args|
          case event
          when :up_to_date
            puts_debug("Branch {{info:#{args[0]}}} is already up-to-date.")
          when :auto_forward
            puts_info("Auto-forwarding #{args[0]} to #{args[1]}")
          when :rebase_command
            puts_debug_git(*args[0])
          end
        end

        if result.updated.positive?
          puts_success("Chain {{info:#{chain.name}}} successfully rebased.")
        else
          puts_info("Chain {{info:#{chain.name}}} is already up-to-date.")
        end
      rescue ChainRebase::VerificationError => e
        puts_error(e.message)
        raise(AbortSilent)
      rescue ChainRebase::Failure => e
        puts_warning(e.original.message)

        puts_error("Cannot merge #{e.branch} onto #{e.parent}.")
        puts_error("Fix the rebase and run {{command:git chain rebase}} again.")
        raise(AbortSilent)
      end
    end
  end
end
