# frozen_string_literal: true

release_workflow = File.expand_path("../.github/workflows/release.yml", __dir__)
workflow = File.read(release_workflow)
ci_workflow = File.read(File.expand_path("../.github/workflows/ci.yml", __dir__))
dispatch_script = File.read(File.expand_path("dispatch-homebrew-release.sh", __dir__))
release_docs = File.read(File.expand_path("../RELEASING.md", __dir__))
abort "missing canonical fork release guard" unless workflow.include?('[[ "$REPOSITORY" == "SijanC147/claude-rc-proxy" ]]')
abort "macos-14 runner remains in source workflows" if workflow.include?("macos-14") || ci_workflow.include?("macos-14")
abort "missing immutable release verification" unless workflow.include?('gh release verify "$RELEASE_TAG"')
abort "full release is not bound to its tag ref" unless workflow.include?(
  '[[ "$GITHUB_REF" == "refs/tags/$RELEASE_TAG" ]]',
)
abort "full release is not bound to its tagged commit" unless workflow.include?(
  '[[ "$GITHUB_SHA" == "$RELEASE_COMMIT" ]]',
)
abort "missing workflow-bound build provenance" unless workflow.include?(
  "actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8",
)
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
  "timeout-minutes: 220",
  "op://CICD/HOMEBREW_TAP_ACTIONS_TOKEN/credential",
]
required_fragments.each do |fragment|
  abort "missing dispatch guard fragment: #{fragment}" unless dispatch_block.include?(fragment)
end
abort "source release workflow still uses the broad tap PAT" if workflow.include?("op://CICD/GH_PAT/credential")
abort "dispatch must use the workflow endpoint" unless dispatch_script.include?(
  'actions/workflows/$workflow/dispatches',
)
abort "dispatch must request the exact run ID" unless dispatch_script.include?("return_run_details: true")
if dispatch_script.match?(%r{repos/\$tap_repository/(?:contents|git|dispatches)})
  abort "Actions-only dispatch path can mutate tap contents"
end
unless release_docs.match?(/Actions:\s+Read and write/) && release_docs.match?(/Contents:\s+No access/)
  abort "release documentation must preserve the Actions-only token boundary"
end
abort "release documentation must require immutable releases" unless release_docs.include?("Enable release immutability")

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
