require "test_helper"

class PartExtractionTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 32)
  PDF = "%PDF-1.7\n%fake\n".b

  # Stands in for Anthropic::Client: records the request, answers +answer+
  # (a Hash sent back as JSON text) or raises +error+.
  class FakeClient
    Block = Struct.new(:type, :text)
    Message = Struct.new(:stop_reason, :content)

    attr_reader :requests

    def initialize(answer: {}, stop_reason: :end_turn, error: nil)
      @answer = answer
      @stop_reason = stop_reason
      @error = error
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      raise @error if @error

      Message.new(@stop_reason, [ Block.new(:text, JSON.generate(@answer)) ])
    end
  end

  setup do
    @org = create_user.organizations.first
    @org.update!(anthropic_api_key: "sk-ant-test")
  end

  def upload(data, type, name)
    file = Tempfile.new([ "upload", File.extname(name) ])
    file.binmode
    file.write(data)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end

  def answer(overrides = {})
    PartExtraction::TEXT_FIELDS.index_with { nil }.merge(
      "category_id" => nil, "footprint_id" => nil, "quantity" => nil, "rohs_compliant" => nil,
      "notes" => nil, "parameters" => []
    ).merge(overrides)
  end

  test "sends the files with the organization's vocabulary and reads the answer back" do
    resistors = create_category(organization: @org, name: "Resistors")
    footprint = create_footprint(organization: @org, name: "0603")
    tolerance = @org.parameter_definitions.create!(name: "Tolerance", value_type: "text")
    client = FakeClient.new(answer: answer(
      "name" => " Resistor 10k 1% 0603 ", "mpn" => "RC0603FR-0710KL", "manufacturer" => "YAGEO",
      "value" => "10k", "category_id" => resistors.id, "footprint_id" => footprint.id,
      "parameters" => [ { "definition_id" => tolerance.id, "value" => "1%" } ],
      "quantity" => 100, "rohs_compliant" => true, "notes" => "Check the power rating."
    ))

    result = PartExtraction.new(@org, client: client).extract(
      [ upload(PNG, "image/png", "label.png"), upload(PDF, "application/pdf", "datasheet.pdf") ], hint: "from the red drawer"
    )

    assert_equal "Resistor 10k 1% 0603", result["name"]
    assert_equal "RC0603FR-0710KL", result["mpn"]
    assert_equal resistors.id, result["category_id"]
    assert_equal footprint.id, result["footprint_id"]
    assert_equal({ tolerance.id.to_s => "1%" }, result["parameters"])
    assert_equal 100, result["quantity"]
    assert_equal true, result["rohs_compliant"]
    assert_equal "Check the power rating.", result["notes"]
    assert_nil result["existing_part"]

    request = client.requests.sole
    assert_equal "claude-opus-5-5", request[:model]
    assert_equal :json_schema, request.dig(:output_config, :format_, :type)
    content = request[:messages].sole[:content]
    assert_equal %w[image document text], content.map { |block| block[:type] }
    assert_equal "image/png", content[0].dig(:source, :media_type)
    assert_equal Base64.strict_encode64(PDF), content[1].dig(:source, :data)
    assert_includes content[2][:text], "Resistors"
    assert_includes content[2][:text], %("id":#{tolerance.id})
    assert_includes content[2][:text], "from the red drawer"
  end

  test "uses the model the organization chose" do
    @org.update!(ai_model: "claude-haiku-5-5")
    client = FakeClient.new(answer: answer)

    PartExtraction.new(@org, client: client).extract([ upload(PNG, "image/png", "a.png") ])

    assert_equal "claude-haiku-5-5", client.requests.sole[:model]
  end

  test "drops ids that aren't the organization's and flags a part already in stock" do
    other = create_organization(name: "Other")
    foreign_category = create_category(organization: other, name: "Theirs")
    foreign_definition = other.parameter_definitions.create!(name: "Tolerance", value_type: "text")
    existing = create_part(organization: @org, name: "NE555 timer", mpn: "NE555P")
    client = FakeClient.new(answer: answer(
      "mpn" => "ne555p", "category_id" => foreign_category.id, "footprint_id" => 999_999,
      "parameters" => [ { "definition_id" => foreign_definition.id, "value" => "5%" } ], "quantity" => -3
    ))

    result = PartExtraction.new(@org, client: client).extract([ upload(PNG, "image/png", "a.png") ])

    assert_nil result["category_id"]
    assert_nil result["footprint_id"]
    assert_empty result["parameters"]
    assert_nil result["quantity"]
    assert_equal({ "id" => existing.id, "name" => "NE555 timer" }, result["existing_part"])
  end

  test "refuses without a key" do
    @org.update!(anthropic_api_key: nil)

    error = assert_raises(PartExtraction::NotConfiguredError) do
      PartExtraction.new(@org, client: FakeClient.new).extract([ upload(PNG, "image/png", "a.png") ])
    end
    assert_match(/Anthropic API key/, error.message)
  end

  test "refuses files it can't send, before calling Claude" do
    client = FakeClient.new

    assert_raises(PartExtraction::InvalidFileError) { PartExtraction.new(@org, client: client).extract([]) }
    assert_raises(PartExtraction::InvalidFileError) do
      PartExtraction.new(@org, client: client).extract([ upload("hello", "text/plain", "notes.txt") ])
    end
    # A type the browser claims but the content contradicts.
    assert_raises(PartExtraction::InvalidFileError) do
      PartExtraction.new(@org, client: client).extract([ upload("not a pdf", "application/pdf", "fake.pdf") ])
    end
    assert_raises(PartExtraction::InvalidFileError) do
      PartExtraction.new(@org, client: client).extract(Array.new(5) { upload(PNG, "image/png", "a.png") })
    end
    big = upload(PNG + ("\x00".b * PartExtraction::MAX_IMAGE_SIZE), "image/png", "big.png")
    error = assert_raises(PartExtraction::InvalidFileError) { PartExtraction.new(@org, client: client).extract([ big ]) }
    assert_match(/big\.png/, error.message)
    assert_empty client.requests
  end

  test "turns API failures and refusals into readable errors" do
    auth_error = Anthropic::Errors::AuthenticationError.new(
      url: URI("https://api.anthropic.com/v1/messages"), status: 401, headers: {}, body: nil, request: nil, response: nil, message: "invalid x-api-key"
    )
    error = assert_raises(PartExtraction::Error) do
      PartExtraction.new(@org, client: FakeClient.new(error: auth_error)).extract([ upload(PNG, "image/png", "a.png") ])
    end
    assert_match(/refused the API key/, error.message)

    connection_error = Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"))
    error = assert_raises(PartExtraction::Error) do
      PartExtraction.new(@org, client: FakeClient.new(error: connection_error)).extract([ upload(PNG, "image/png", "a.png") ])
    end
    assert_match(/Could not reach Anthropic/, error.message)

    error = assert_raises(PartExtraction::Error) do
      PartExtraction.new(@org, client: FakeClient.new(stop_reason: :refusal)).extract([ upload(PNG, "image/png", "a.png") ])
    end
    assert_match(/declined/, error.message)
  end

  test "sends with a short timeout and no retry" do
    client = FakeClient.new(answer: answer)

    PartExtraction.new(@org, client: client).extract([ upload(PNG, "image/png", "a.png") ])

    assert_equal({ timeout: PartExtraction::TIMEOUT, max_retries: 0 }, client.requests.sole[:request_options])
    assert_operator PartExtraction::TIMEOUT, :<=, 60
  end

  test "refuses files that together exceed what the API takes" do
    client = FakeClient.new(answer: answer)
    half = PDF + ("\x00".b * (PartExtraction::MAX_TOTAL_SIZE / 2))

    error = assert_raises(PartExtraction::InvalidFileError) do
      PartExtraction.new(@org, client: client).extract([ upload(half, "application/pdf", "a.pdf"), upload(half, "application/pdf", "b.pdf") ])
    end
    assert_match(/Together, the files are larger than 20 MB/, error.message)
    assert_empty client.requests
  end

  test "a read waits for a free slot and gives up when the server is busy" do
    client = FakeClient.new(answer: answer)
    PartExtraction::SLOTS.acquire(PartExtraction::MAX_CONCURRENT)
    begin
      stub_singleton(PartExtraction, :queue_wait, -> { 0 }) do
        error = assert_raises(PartExtraction::BusyError) do
          PartExtraction.new(@org, client: client).extract([ upload(PNG, "image/png", "a.png") ])
        end
        assert_match(/Another AI read is running/, error.message)
      end
    ensure
      PartExtraction::SLOTS.release(PartExtraction::MAX_CONCURRENT)
    end
    assert_empty client.requests

    # The slot is given back after a read, even a failed one.
    failing = FakeClient.new(error: Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages")))
    assert_raises(PartExtraction::Error) { PartExtraction.new(@org, client: failing).extract([ upload(PNG, "image/png", "a.png") ]) }
    assert_equal PartExtraction::MAX_CONCURRENT, PartExtraction::SLOTS.available_permits
  end

  # Stands in for Anthropic::Client in key checks: models.list answers or raises.
  class FakeModelsClient
    def initialize(error: nil) = @error = error
    def models = self

    def list(**)
      raise @error if @error

      []
    end
  end

  test "key_problem checks the format, then asks Anthropic" do
    url = URI("https://api.anthropic.com/v1/models")
    refused = Anthropic::Errors::AuthenticationError.new(url: url, status: 401, headers: {}, body: nil, request: nil, response: nil, message: "invalid x-api-key")

    assert_match(/doesn't look like an Anthropic API key/, PartExtraction.key_problem("hello", client: FakeModelsClient.new))
    assert_nil PartExtraction.key_problem("sk-ant-good", client: FakeModelsClient.new)
    assert_match(/Anthropic refused this key/, PartExtraction.key_problem("sk-ant-bad", client: FakeModelsClient.new(error: refused)))
    # Anthropic out of reach: the key can't be checked, so it's accepted.
    assert_nil PartExtraction.key_problem("sk-ant-offline", client: FakeModelsClient.new(error: Anthropic::Errors::APIConnectionError.new(url: url)))
  end

  test "answers in the user's language" do
    client = FakeClient.new(answer: answer)

    I18n.with_locale(:fr) { PartExtraction.new(@org, client: client).extract([ upload(PNG, "image/png", "a.png") ]) }

    assert_includes client.requests.sole[:messages].sole[:content].last[:text], %("language":"French")
  end
end
