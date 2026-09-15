#!/usr/bin/env ruby
# frozen_string_literal: true

# Fail fast with a clear message when ASC_* secrets produce a JWT Apple rejects.
# Used by ios_release.yml before ci_build_number so the log is actionable.
#
# Usage (from ios/): bundle exec ruby ci/verify-asc-api-key.rb

require "json"
require "net/http"
require "openssl"
require "uri"

key_id = ENV.fetch("ASC_KEY_ID", "").strip
issuer_id = ENV.fetch("ASC_ISSUER_ID", "").strip
key_path = ENV.fetch("ASC_KEY_FILEPATH", "").strip
team_id = ENV.fetch("APPLE_TEAM_ID", "").strip

def fail!(msg)
  warn "ERROR: #{msg}"
  exit 1
end

fail!("ASC_KEY_ID is empty") if key_id.empty?
fail!("ASC_ISSUER_ID is empty") if issuer_id.empty?
fail!("ASC_KEY_FILEPATH is empty") if key_path.empty?
fail!("ASC_KEY_FILEPATH does not exist: #{key_path}") unless File.file?(key_path)

unless key_id.match?(/\A[A-Z0-9]{10}\z/)
  fail!(
    "ASC_KEY_ID=#{key_id.inspect} does not look like an App Store Connect Key ID " \
    "(expected 10 A–Z/0–9 chars). You may have pasted APPLE_TEAM_ID or the Issuer ID."
  )
end

unless issuer_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
  fail!(
    "ASC_ISSUER_ID=#{issuer_id.inspect} is not a UUID. Copy Issuer ID from the top of " \
    "App Store Connect → Users and Access → Integrations → App Store Connect API."
  )
end

if !team_id.empty? && !team_id.match?(/\A[A-Z0-9]{10}\z/)
  fail!("APPLE_TEAM_ID=#{team_id.inspect} should be a 10-character Apple Team ID")
end

pem = File.read(key_path)
unless pem.include?("BEGIN PRIVATE KEY")
  fail!(
    "ASC private key at #{key_path} is not a PEM private key " \
    "(missing BEGIN PRIVATE KEY). Re-encode AuthKey_#{key_id}.p8 as base64 for " \
    "ASC_PRIVATE_KEY_B64 — see docs/IOS_RELEASE.md."
  )
end

begin
  OpenSSL::PKey.read(pem)
rescue OpenSSL::PKey::PKeyError => e
  fail!("ASC private key does not parse with OpenSSL: #{e.message}")
end

begin
  require "spaceship"
rescue LoadError
  fail!("spaceship (fastlane) is not installed — run bundle install in ios/ first")
end

token = Spaceship::ConnectAPI::Token.create(
  key_id: key_id,
  issuer_id: issuer_id,
  filepath: key_path,
  duration: 500
)

uri = URI("https://api.appstoreconnect.apple.com/v1/apps?limit=1")
req = Net::HTTP::Get.new(uri)
req["Authorization"] = "Bearer #{token.text}"
req["Accept"] = "application/json"

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.open_timeout = 30
http.read_timeout = 30
res = http.request(req)

if res.code.to_i == 401 || res.code.to_i == 403
  body = res.body.to_s[0, 500]
  fail!(
    "App Store Connect rejected the API key (HTTP #{res.code}).\n" \
    "  Key ID length=#{key_id.length}, Issuer looks like UUID, .p8 parses.\n" \
    "  Usual causes: Key ID does not match this .p8, Issuer ID is wrong, or the\n" \
    "  key was revoked. Regenerate a Team key in App Store Connect, set\n" \
    "  ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY_B64 together, re-run.\n" \
    "  Response: #{body}"
  )
end

unless res.is_a?(Net::HTTPSuccess)
  fail!("App Store Connect probe failed HTTP #{res.code}: #{res.body.to_s[0, 500]}")
end

warn "OK: ASC API key authenticates (Key ID …#{key_id[-4]}, apps probe HTTP #{res.code})"
