# frozen_string_literal: true

require "minitest/autorun"
require_relative "homebrew_formula"

class HomebrewFormulaTest < Minitest::Test
  TEMPLATE = File.expand_path("../packaging/homebrew/claude-rc-proxy.rb.tmpl", __dir__)
  ARM_SHA = "a" * 64
  AMD_SHA = "b" * 64

  def render(version: "1.2.3", arm64_sha: ARM_SHA, amd64_sha: AMD_SHA)
    HomebrewFormula.render(
      template: File.read(TEMPLATE),
      version: version,
      arm64_sha: arm64_sha,
      amd64_sha: amd64_sha,
    )
  end

  def metadata_free(formula)
    formula.lines.reject do |line|
      line.include?("claude-rc-proxy-darwin-") || line.match?(/^\s*sha256 "/)
    end.join
  end

  def test_render_creates_service_formula_without_secrets
    formula = render

    assert_includes formula, "class ClaudeRcProxy < Formula"
    assert_includes formula, "releases/download/v1.2.3/claude-rc-proxy-darwin-arm64.tar.gz"
    assert_includes formula, "releases/download/v1.2.3/claude-rc-proxy-darwin-amd64.tar.gz"
    assert_includes formula, %(sha256 "#{ARM_SHA}")
    assert_includes formula, %(sha256 "#{AMD_SHA}")
    assert_includes formula, "if Hardware::CPU.arm?"
    assert_includes formula, "depends_on :macos"
    assert_includes formula, "service do"
    assert_includes formula, "~/.homebrew/services/claude-rc-proxy.env"
    assert_includes formula, "assert_match version.to_s"
    refute_match(/@[A-Z0-9_]+@/, formula)
    refute_includes formula, "local-loopback-sentinel"
    refute_includes formula, "rootCA-key"
  end

  def test_update_changes_only_release_metadata_and_is_idempotent
    original = render
    customized = original.sub("  service do\n", "  # tap-owned custom marker\n  service do\n")

    updated = HomebrewFormula.update(
      formula: customized,
      version: "2.0.0",
      arm64_sha: "c" * 64,
      amd64_sha: "d" * 64,
    )

    assert_equal metadata_free(customized), metadata_free(updated)
    assert_includes updated, "# tap-owned custom marker"
    assert_includes updated, "releases/download/v2.0.0/claude-rc-proxy-darwin-arm64.tar.gz"
    assert_includes updated, %(sha256 "#{"c" * 64}")
    assert_equal updated, HomebrewFormula.update(
      formula: updated,
      version: "2.0.0",
      arm64_sha: "c" * 64,
      amd64_sha: "d" * 64,
    )
  end

  def test_update_rejects_unexpected_structure
    formula = render
    duplicate_block = \
      %(  url "https://example.invalid/claude-rc-proxy-darwin-arm64.tar.gz"\n) +
      %(  sha256 "#{ARM_SHA}"\n\n) +
      "  if Hardware::CPU.arm?\n"
    duplicated = formula.sub(
      "  if Hardware::CPU.arm?\n",
      duplicate_block,
    )

    assert_raises(HomebrewFormula::Error) do
      HomebrewFormula.update(
        formula: duplicated,
        version: "2.0.0",
        arm64_sha: "c" * 64,
        amd64_sha: "d" * 64,
      )
    end
  end

  def test_update_rejects_downgrade
    assert_raises(HomebrewFormula::Error) do
      HomebrewFormula.update(
        formula: render(version: "2.0.0"),
        version: "1.9.9",
        arm64_sha: "c" * 64,
        amd64_sha: "d" * 64,
      )
    end
  end

  def test_rejects_invalid_metadata
    assert_raises(HomebrewFormula::Error) { render(version: "v1.2.3") }
    assert_raises(HomebrewFormula::Error) { render(arm64_sha: "not-a-sha") }
    assert_raises(HomebrewFormula::Error) { render(amd64_sha: "A" * 64) }
  end
end
