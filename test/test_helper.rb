ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

    def create_user(email: "user_#{SecureRandom.hex(4)}@example.com", **attrs)
      User.create!(firstname: "Test", lastname: "User", email: email, password: "password123", **attrs)
    end

    def create_project(organization:, name: "Project #{SecureRandom.hex(4)}", **attrs)
      Project.create!(organization: organization, name: name, **attrs)
    end

    def create_order(organization:, supplier: nil, **attrs)
      supplier ||= create_supplier(organization: organization)
      Order.create!(organization: organization, supplier: supplier, **attrs)
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
