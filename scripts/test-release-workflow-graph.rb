# frozen_string_literal: true

release_workflow = File.expand_path("../.github/workflows/release.yml", __dir__)
workflow = File.read(release_workflow)
abort "missing canonical fork release guard" unless workflow.include?('[[ "$REPOSITORY" == "SijanC147/claude-rc-proxy" ]]')
homebrew_jobs = workflow.scan(/^  (homebrew[^:]*):/).flatten
abort "unexpected Homebrew jobs: #{homebrew_jobs.inspect}" unless homebrew_jobs == ["homebrew-dispatch"]

dispatch_block = workflow[/^  homebrew-dispatch:\n(?<body>.*)\z/m, :body]
abort "missing Homebrew dispatch job" unless dispatch_block
required_fragments = [
  "needs.validate.outputs.stable == 'true'",
  "needs.validate.outputs.mode == 'full' && needs.release.result == 'success'",
  "needs.validate.outputs.mode == 'homebrew-only' && needs.release.result == 'skipped'",
  "SijanC147/homebrew-hextap",
  "version: 2.39.0",
]
required_fragments.each do |fragment|
  abort "missing dispatch guard fragment: #{fragment}" unless dispatch_block.include?(fragment)
end

eligible = lambda do |stable:, mode:, release_result:, cancelled: false|
  !cancelled && stable && (
    (mode == "full" && release_result == "success") ||
    (mode == "homebrew-only" && release_result == "skipped")
  )
end

abort "stable full release must dispatch" unless eligible.call(stable: true, mode: "full", release_result: "success")
abort "stable recovery must dispatch" unless eligible.call(stable: true, mode: "homebrew-only", release_result: "skipped")
abort "prerelease must not dispatch" if eligible.call(stable: false, mode: "full", release_result: "success")
abort "cancelled release must not dispatch" if eligible.call(stable: true, mode: "full", release_result: "success", cancelled: true)

puts "release workflow graph tests passed"
