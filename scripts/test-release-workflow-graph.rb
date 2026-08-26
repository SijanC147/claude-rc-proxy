# frozen_string_literal: true

require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
WORKFLOW_ROOT = File.join(REPO_ROOT, ".github", "workflows")
CALLER_PATH = File.join(WORKFLOW_ROOT, "hextap-release.yml")
LEGACY_CALLER_PATH = File.join(WORKFLOW_ROOT, "release.yml")
TOOLKIT_CALL = "SijanC147/hextap-toolkit/.github/workflows/release-go.yml"
TOOLKIT_SHA = "ddc8371e522a968b051fba26a64bc0d4c39d4d8b"
TOOLKIT_TAG = "v0.1.2"
RELEASE_TAGS = ["v0.1.0", "v1.2.3", "v1.2.3-rc.1"].freeze

EXPECTED_CALLER = <<~YAML
  name: Hextap release

  on:
    push:
      tags:
        - "v*"
    workflow_dispatch:
      inputs:
        tag:
          description: Existing stable release tag
          required: true
          type: string

  permissions:
    contents: write
    attestations: write
    id-token: write

  jobs:
    release:
      uses: #{TOOLKIT_CALL}@#{TOOLKIT_SHA} # #{TOOLKIT_TAG}
      with:
        manifest_path: .hextap.json
        tag: ${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}
        mode: ${{ github.event_name == 'workflow_dispatch' && 'homebrew-only' || 'full' }}
      secrets:
        op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
YAML

def workflow_document(path)
  YAML.safe_load(File.read(path), aliases: true) || {}
rescue Psych::SyntaxError => e
  abort "invalid workflow YAML #{path}: #{e.message}"
end

def pattern_matches?(patterns, tag)
  included = false
  patterns.each do |raw_pattern|
    pattern = raw_pattern.to_s
    negated = pattern.start_with?("!")
    candidate = negated ? pattern.delete_prefix("!") : pattern
    included = !negated if File.fnmatch?(candidate, tag, File::FNM_EXTGLOB)
  end
  included
end

def responds_to_release_tag?(document)
  triggers = document["on"] || document[true]
  return triggers == "push" || (triggers.is_a?(Array) && triggers.include?("push")) unless triggers.is_a?(Hash)
  return false unless triggers.key?("push")

  push = triggers["push"]
  return true if push.nil?
  return false unless push.is_a?(Hash)

  if push.key?("tags")
    patterns = Array(push["tags"])
    return RELEASE_TAGS.any? { |tag| pattern_matches?(patterns, tag) }
  end

  if push.key?("tags-ignore")
    ignored = Array(push["tags-ignore"])
    return RELEASE_TAGS.any? do |tag|
      ignored.none? { |pattern| File.fnmatch?(pattern.to_s, tag, File::FNM_EXTGLOB) }
    end
  end

  !(push.key?("branches") || push.key?("branches-ignore"))
end

abort "legacy release caller remains: #{LEGACY_CALLER_PATH}" if File.exist?(LEGACY_CALLER_PATH)
abort "managed Hextap caller is missing: #{CALLER_PATH}" unless File.file?(CALLER_PATH)

caller = File.read(CALLER_PATH)
abort "managed Hextap caller snapshot changed" unless caller == EXPECTED_CALLER
abort "caller uses mutable @main" if caller.include?("@main")
abort "caller inherits repository secrets" if caller.include?("secrets: inherit")
unless caller.scan("op_service_account_token: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}").length == 1
  abort "caller must explicitly map OP_SERVICE_ACCOUNT_TOKEN exactly once"
end

workflow_paths = Dir.glob(File.join(WORKFLOW_ROOT, "*.{yml,yaml}")).sort
release_workflows = workflow_paths.select { |path| responds_to_release_tag?(workflow_document(path)) }
unless release_workflows == [CALLER_PATH]
  abort "expected exactly one v* tag workflow, found: #{release_workflows.join(", ")}"
end

toolkit_calls = workflow_paths.flat_map do |path|
  File.readlines(path, chomp: true).filter_map do |line|
    line.strip if line.match?(/^\s*uses:\s+#{Regexp.escape(TOOLKIT_CALL)}@/)
  end
end
expected_call = "uses: #{TOOLKIT_CALL}@#{TOOLKIT_SHA} # #{TOOLKIT_TAG}"
abort "unexpected reusable Hextap callers: #{toolkit_calls.inspect}" unless toolkit_calls == [expected_call]

mutable_calls = workflow_paths.flat_map do |path|
  File.readlines(path, chomp: true).grep(/^\s*uses:\s+\S+@main(?:\s|$)/).map { |line| "#{path}: #{line.strip}" }
end
abort "mutable workflow calls remain: #{mutable_calls.join(", ")}" unless mutable_calls.empty?

puts "immutable Hextap caller graph and snapshot tests passed"
