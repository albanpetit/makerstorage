require "test_helper"

class ParameterValueTest < ActiveSupport::TestCase
  test "reads values the way they are typed on parts and in BOMs" do
    {
      [ "4k7", "Ω" ] => 4700.0,
      [ "4K7", "Ω" ] => 4700.0,
      [ "4.7 kΩ", "Ω" ] => 4700.0,
      [ "4,7k", "Ω" ] => 4700.0,
      [ "10R", "Ω" ] => 10.0,
      [ "4R7", "Ω" ] => 4.7,
      [ "1M", "Ω" ] => 1_000_000.0,
      [ "1meg", "Ω" ] => 1_000_000.0,
      [ "10 ohms", "Ω" ] => 10.0,
      [ "100nF", "F" ] => 1.0e-7,
      [ "2u2", "F" ] => 2.2e-6,
      [ "4.7µF", "F" ] => 4.7e-6,
      [ "1/4 W", "W" ] => 0.25,
      [ "125mW", "W" ] => 0.125,
      [ "±5 %", "%" ] => 5.0,
      [ "3V3", "V" ] => 3.3,
      [ "50V", "V" ] => 50.0,
      [ "16MHz", "Hz" ] => 16_000_000.0,
      [ "500mA", "A" ] => 0.5,
      [ "85°C", "°C" ] => 85.0,
      [ "1e-6", "F" ] => 1.0e-6,
      [ "8", nil ] => 8.0
    }.each do |(text, unit), expected|
      assert_in_delta expected, ParameterValue.parse(text, unit), expected.abs * 1e-9, "#{text} in #{unit}"
    end
  end

  test "keeps twelve significant digits so equal values compare equal" do
    assert_equal 1.0e-7, ParameterValue.parse("100n", "F")
    assert_equal ParameterValue.parse("0.1µF", "F"), ParameterValue.parse("100nF", "F")
  end

  test "anything else is not a number in the unit" do
    [ "", "abc", "X7R", "10 kV", "4k7k", "1/0", "--5" ].each do |text|
      assert_nil ParameterValue.parse(text, "Ω"), text
    end
  end

  test "formats SI units with a prefix and four significant digits" do
    assert_equal "4.7 kΩ", ParameterValue.format(4700.0, "Ω")
    assert_equal "100 nF", ParameterValue.format(1.0e-7, "F")
    assert_equal "2.2 µF", ParameterValue.format(2.2e-6, "F")
    assert_equal "1 MΩ", ParameterValue.format(999_999.9, "Ω")
    assert_equal "250 mW", ParameterValue.format(0.25, "W")
    assert_equal "0 V", ParameterValue.format(0.0, "V")
  end

  test "formats other units as stored" do
    assert_equal "5%", ParameterValue.format(5.0, "%")
    assert_equal "85 °C", ParameterValue.format(85.0, "°C")
    assert_equal "0.5 mm", ParameterValue.format(0.5, "mm")
    assert_equal "1000000", ParameterValue.format(1_000_000.0, nil)
    assert_nil ParameterValue.format(nil, "Ω")
  end
end
