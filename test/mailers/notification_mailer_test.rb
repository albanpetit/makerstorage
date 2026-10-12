require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "digest lists the alerts and links to the organization's alerts page" do
    org = create_organization(name: "Fablab Amiens")
    user = create_user(firstname: "Ada")
    part = create_part(organization: org, name: "LM358 op-amp", mpn: "LM358DR", min_stock_threshold: 5)
    order = create_order(organization: org, reference: "PO-7", status: "shipped", expected_delivery: Date.new(2026, 10, 10))

    mail = NotificationMailer.digest(user: user, digest: NotificationDigest.new(org, date: Date.new(2026, 10, 12)))

    assert_equal [ user.email ], mail.to
    assert_equal "Fablab Amiens: 1 low-stock part and 1 late order", mail.subject
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Hello Ada"
      assert_includes body, "LM358 op-amp"
      assert_includes body, part.ipn
      assert_includes body, "PO-7"
      assert_includes body, order.supplier.name
      assert_includes body, "2 days late"
      assert_includes body, "/alerts?organization_id=#{org.id}"
      assert_includes body, "/profile"
      assert_not_includes body, "an account action was requested"
    end
  end
end
