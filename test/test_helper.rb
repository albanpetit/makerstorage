ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Build the frontend once, here, before parallel workers fork. With Vite's test
# autoBuild every worker would otherwise rebuild a stale bundle at the same
# time and race on public/vite-test (one can read a half-written manifest:
# "Vite Ruby can't find entrypoints/application.css"). A no-op when the build
# is already fresh.
ViteRuby.instance.commands.build if ViteRuby.config.auto_build

# Routes (and therefore Devise's mappings) are loaded lazily on first request.
# Force them to load now so Devise::Test::IntegrationHelpers#sign_in works
# even when called before any request in a test.
Rails.application.reload_routes!

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Every request (integration or system) comes from the same IP, so auth rate
    # limits would otherwise carry over from one test to the next.
    setup { Rails.application.config.x.rate_limit_store&.clear }

    # Add more helper methods to be used by all tests here...

    # Temporarily replaces a singleton (class/module) method for the duration of
    # the block, restoring the original afterwards. Minitest 6 dropped the
    # bundled `minitest/mock`, so this covers the small amount of stubbing we need.
    def stub_singleton(receiver, name, replacement)
      singleton = receiver.singleton_class
      original = singleton.instance_method(name)
      singleton.send(:define_method, name) { |*args, **kwargs, &blk| replacement.call(*args, **kwargs, &blk) }
      yield
    ensure
      singleton.send(:define_method, name, original)
    end

    # Runs the block with email verification (config.x.email_verification) on
    # or off, as an instance with or without SMTP would.
    def with_email_verification(enabled)
      original = Rails.configuration.x.email_verification
      Rails.configuration.x.email_verification = enabled
      yield
    ensure
      Rails.configuration.x.email_verification = original
    end

    # Runs the block with the email digest (config.x.email_notifications) on or
    # off, as an instance with or without SMTP would.
    def with_email_notifications(enabled)
      original = Rails.configuration.x.email_notifications
      Rails.configuration.x.email_notifications = enabled
      yield
    ensure
      Rails.configuration.x.email_notifications = original
    end

    # Stands in for GithubClient: +commits+ maps a ref (nil for the default
    # branch) to a SHA, +archives+ maps a SHA to the repository's files
    # ({ "path" => content }), zipped the way GitHub does under one
    # "<owner>-<repo>-<sha>/" folder. Records the calls in #calls.
    class FakeGithub
      attr_reader :calls, :tokens

      def initialize(commits: {}, archives: {}, error: nil)
        @commits, @archives, @error = commits, archives, error
        @calls = []
        @tokens = []
      end

      def commit_sha(repository, ref)
        @calls << [ :commit_sha, repository, ref ]
        raise GithubClient::Error, @error if @error

        @commits.fetch(ref) { raise GithubClient::Error, "Could not find #{repository} at “#{ref}” on GitHub." }
      end

      def download_archive(repository, sha)
        @calls << [ :download_archive, repository, sha ]
        file = Tempfile.new([ "github", ".zip" ], binmode: true)
        Zip::OutputStream.open(file.path) do |zip|
          @archives.fetch(sha).each do |name, content|
            zip.put_next_entry("#{repository.tr('/', '-')}-#{sha.first(7)}/#{name}")
            zip.write(content)
          end
        end
        yield file.path
      ensure
        file&.close!
      end
    end

    # Runs the block with GithubClient.new handing out +fake+ (a FakeGithub).
    def with_fake_github(fake, &block)
      stub_singleton(GithubClient, :new, ->(token: nil) { fake.tokens << token; fake }, &block)
    end

    def create_organization(name: "Test Org #{SecureRandom.hex(4)}", **attrs)
      Organization.create!(name: name, **attrs)
    end

    def create_category(organization:, name: "Category #{SecureRandom.hex(4)}", **attrs)
      Category.create!(organization: organization, name: name, **attrs)
    end

    def create_footprint(organization:, name: "Footprint #{SecureRandom.hex(4)}", **attrs)
      Footprint.create!(organization: organization, name: name, **attrs)
    end

    def create_tag(organization:, name: "Tag #{SecureRandom.hex(4)}", **attrs)
      Tag.create!(organization: organization, name: name, **attrs)
    end

    def create_part(organization:, category: nil, name: "Part #{SecureRandom.hex(4)}", **attrs)
      category ||= create_category(organization: organization)
      Part.create!(organization: organization, category: category, name: name, **attrs)
    end

    def create_storage_location(organization:, name: "Location #{SecureRandom.hex(4)}", location_type: "room", **attrs)
      StorageLocation.create!(organization: organization, name: name, location_type: location_type, **attrs)
    end

    def create_supplier(organization:, name: "Supplier #{SecureRandom.hex(4)}", **attrs)
      Supplier.create!(organization: organization, name: name, **attrs)
    end

    # Confirmed by default, like any account that has answered its confirmation
    # mail; pass confirmed_at: nil for one that hasn't.
    def create_user(email: "user_#{SecureRandom.hex(4)}@example.com", **attrs)
      User.create!(firstname: "Test", lastname: "User", email: email, password: "password123", confirmed_at: Time.current, **attrs)
    end

    def create_project(organization:, name: "Project #{SecureRandom.hex(4)}", **attrs)
      Project.create!(organization: organization, name: name, **attrs)
    end

    def create_order(organization:, supplier: nil, **attrs)
      supplier ||= create_supplier(organization: organization)
      Order.create!(organization: organization, supplier: supplier, **attrs)
    end

    def create_oauth_client(name: "Claude", redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ])
      OauthClient.create!(name: name, redirect_uris: redirect_uris)
    end

    # A PKCE verifier and its S256 challenge.
    def pkce_pair
      verifier = SecureRandom.urlsafe_base64(48)
      [ verifier, Base64.urlsafe_encode64(::Digest::SHA256.digest(verifier), padding: false) ]
    end

    # Runs the whole OAuth grant for +user+ on +organization+ and returns the
    # token hash (access_token, refresh_token…) an MCP client would receive.
    # +write+ also grants the mcp:write scope.
    def connect_mcp_client(user:, organization:, client: create_oauth_client, write: false)
      verifier, challenge = pkce_pair
      redirect_uri = client.redirect_uris.first
      code = OauthAuthorization.grant!(client: client, user: user, organization: organization,
                                       redirect_uri: redirect_uri, code_challenge: challenge, write: write)
      OauthAuthorization.exchange_code!(client: client, code: code, redirect_uri: redirect_uri, code_verifier: verifier)
    end

    # Counts the real SQL queries a block fires, ignoring cached hits, schema
    # introspection, and transaction control. Used to pin N+1 fixes shut: run
    # the same request against a small and a larger dataset and assert the count
    # doesn't grow with collection size.
    def count_queries
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:cached]
        next if payload[:name] == "SCHEMA"
        next if payload[:sql] =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

        count += 1
      end
      # The SQL query cache persists across requests inside one integration test,
      # so a repeated identical request would be served from cache and undercount.
      # Clear it first to measure the real queries this block fires.
      ActiveRecord::Base.connection.clear_query_cache
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
end
