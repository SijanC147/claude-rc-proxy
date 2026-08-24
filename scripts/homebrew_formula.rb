# frozen_string_literal: true

module HomebrewFormula
  class Error < StandardError; end

  REPOSITORY = "SijanC147/claude-rc-proxy"
  STABLE_VERSION = /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/.freeze
  SHA256 = /\A[0-9a-f]{64}\z/.freeze
  TOKEN_PATTERN = /@[A-Z0-9_]+@/.freeze

  module_function

  def validate_metadata!(version:, arm64_sha:, amd64_sha:)
    raise Error, "invalid stable version: #{version}" unless STABLE_VERSION.match?(version)
    raise Error, "invalid arm64 SHA-256" unless SHA256.match?(arm64_sha)
    raise Error, "invalid amd64 SHA-256" unless SHA256.match?(amd64_sha)
  end

  def release_url(version, architecture)
    "https://github.com/#{REPOSITORY}/releases/download/v#{version}/" \
      "claude-rc-proxy-darwin-#{architecture}.tar.gz"
  end

  def render(template:, version:, arm64_sha:, amd64_sha:)
    validate_metadata!(version: version, arm64_sha: arm64_sha, amd64_sha: amd64_sha)
    replacements = {
      "@ARM64_URL@" => release_url(version, "arm64"),
      "@ARM64_SHA256@" => arm64_sha,
      "@AMD64_URL@" => release_url(version, "amd64"),
      "@AMD64_SHA256@" => amd64_sha,
    }

    rendered = template.dup
    replacements.each do |token, value|
      count = rendered.scan(token).length
      raise Error, "expected exactly one #{token}, found #{count}" unless count == 1

      rendered.sub!(token, value)
    end
    leftovers = rendered.scan(TOKEN_PATTERN).uniq
    raise Error, "unresolved template tokens: #{leftovers.join(", ")}" unless leftovers.empty?

    rendered
  end

  def update(formula:, version:, arm64_sha:, amd64_sha:)
    validate_metadata!(version: version, arm64_sha: arm64_sha, amd64_sha: amd64_sha)
    current_version = current_version(formula)
    if (version_parts(version) <=> version_parts(current_version)).negative?
      raise Error, "refusing to downgrade Formula from #{current_version} to #{version}"
    end

    updated = formula.dup
    updated = replace_asset_block(
      updated,
      asset: "claude-rc-proxy-darwin-arm64.tar.gz",
      url: release_url(version, "arm64"),
      sha256: arm64_sha,
    )
    replace_asset_block(
      updated,
      asset: "claude-rc-proxy-darwin-amd64.tar.gz",
      url: release_url(version, "amd64"),
      sha256: amd64_sha,
    )
  end

  def current_version(formula)
    pattern = %r{github\.com/#{Regexp.escape(REPOSITORY)}/releases/download/v(#{STABLE_VERSION.source[2..-3]})/claude-rc-proxy-darwin-(?:arm64|amd64)\.tar\.gz}
    versions = formula.scan(pattern).map(&:first)
    unique_versions = versions.uniq
    unless versions.length == 2 && unique_versions.length == 1
      raise Error, "expected two release URLs with one current version"
    end

    unique_versions.first
  end
  private_class_method :current_version

  def version_parts(version)
    version.split(".").map(&:to_i)
  end
  private_class_method :version_parts

  def replace_asset_block(formula, asset:, url:, sha256:)
    pattern = /^([ \t]*)url "[^"\n]*\/#{Regexp.escape(asset)}"\n([ \t]*)sha256 "[0-9a-f]{64}"$/
    count = formula.scan(pattern).length
    raise Error, "expected exactly one metadata block for #{asset}, found #{count}" unless count == 1

    formula.sub(pattern) do
      match = Regexp.last_match
      %(#{match[1]}url "#{url}"\n#{match[2]}sha256 "#{sha256}")
    end
  end
  private_class_method :replace_asset_block
end
