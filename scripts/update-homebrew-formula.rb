#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "tempfile"
require_relative "homebrew_formula"

options = {}
OptionParser.new do |parser|
  parser.banner = "usage: update-homebrew-formula.rb --formula PATH --template PATH --version VERSION --arm64-sha SHA --amd64-sha SHA"
  parser.on("--formula PATH") { |value| options[:formula] = value }
  parser.on("--template PATH") { |value| options[:template] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--arm64-sha SHA") { |value| options[:arm64_sha] = value }
  parser.on("--amd64-sha SHA") { |value| options[:amd64_sha] = value }
end.parse!

required = %i[formula template version arm64_sha amd64_sha]
missing = required.reject { |key| options[key] && !options[key].empty? }
abort "missing required options: #{missing.join(", ")}" unless missing.empty?

formula_path = File.expand_path(options[:formula])
template_path = File.expand_path(options[:template])
created = !File.exist?(formula_path)

contents = if created
  HomebrewFormula.render(
    template: File.read(template_path),
    version: options[:version],
    arm64_sha: options[:arm64_sha],
    amd64_sha: options[:amd64_sha],
  )
else
  HomebrewFormula.update(
    formula: File.read(formula_path),
    version: options[:version],
    arm64_sha: options[:arm64_sha],
    amd64_sha: options[:amd64_sha],
  )
end

FileUtils.mkdir_p(File.dirname(formula_path), mode: 0o755)
mode = File.exist?(formula_path) ? File.stat(formula_path).mode & 0o777 : 0o644
Tempfile.create([".claude-rc-proxy", ".rb"], File.dirname(formula_path)) do |temp|
  temp.write(contents)
  temp.flush
  temp.fsync
  temp.chmod(mode)
  temp.close
  File.rename(temp.path, formula_path)
end

puts "#{created ? "created" : "updated"} #{formula_path}"
