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

    # Add more helper methods to be used by all tests here...

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
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
