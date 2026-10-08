require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  # The Docker entrypoint runs `db:prepare`, which loads the seeds on a fresh
  # database: in production they must be a no-op, not an abort that stops the
  # container on its first boot.
  test "loading the seeds outside development and test skips without creating anything" do
    original_env = Rails.env
    Rails.env = "production"

    assert_no_difference -> { User.count } do
      assert_output(/Skipping db\/seeds\.rb/) { load Rails.root.join("db/seeds.rb") }
    end
  ensure
    Rails.env = original_env
  end
end
