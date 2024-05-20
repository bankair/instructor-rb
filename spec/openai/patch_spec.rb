# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Instructor::OpenAI::Patch do
  subject(:patched_client) { Instructor.patch(OpenAI::Client) }

  let(:user_model) do
    Class.new do
      include EasyTalk::Model

      def self.name
        'User'
      end

      def self.instructions
        "Extract the user's name and age."
      end

      define_schema do
        title 'SomeUser'
        property :name, String
        property :age, Integer
      end
    end
  end

  it 'returns the patched client' do
    expect(patched_client).to eq(OpenAI::Client)
  end

  context 'when generating description' do
    let(:client) { patched_client.new }

    it "returns the model's instructions" do
      expect(client.generate_description(user_model)).to eq("Extract the user's name and age.")
    end

    it 'returns the default description when the model does not have instructions' do
      model = Class.new do
        include EasyTalk::Model

        def self.name
          'User'
        end

        define_schema {}
      end

      expect(client.generate_description(model)).to eq('Correctly extracted `User` with all the required parameters with correct types')
    end
  end

  context 'with a new instance of the patched client' do
    it 'returns an instance of the patched client' do
      expect(patched_client.new).to be_an_instance_of(OpenAI::Client)
    end

    pending 'receives the chat method with the expected arguments' do
      client.chat(parameters: {}, response_model: nil)
      expect(client).to have_received(:chat).with(parameters: {}, response_model: nil)
    end

    it 'does not require the response model argument' do
      expect { client.chat(parameters: {}) }.not_to raise_error(ArgumentError)
    end

    it 'does require the parameters argument' do
      client = patched_client.new
      expect { client.chat }.to raise_error(ArgumentError, 'missing keyword: :parameters')
    end

    describe 'when setting the function_name' do
      it 'returns the function_name based on the schema title' do
        client = patched_client.new
        expect(client.generate_function_name(user_model)).to eq('SomeUser')
      end

      it 'returns the class name when the schema title is not defined' do
        model = Class.new do
          include EasyTalk::Model

          def self.name
            'User'
          end

          define_schema {}
        end

        client = patched_client.new
        expect(client.generate_function_name(model)).to eq('User')
      end
    end

    it 'returns an object with the expected valid attribute values', vcr: 'patching_spec/valid_response' do
      client = patched_client.new

      user = client.chat(
        parameters: {
          model: 'gpt-3.5-turbo',
          messages: [{ role: 'user', content: 'Extract Jason is 25 years old' }]
        },
        response_model: user_model
      )

      expect(user.name).to eq('Jason')
      expect(user.age).to eq(25)
    end
  end

  context 'with retry mechanism' do
    let(:client) { patched_client.new }
    let(:parameters) { { key: 'value' } }
    let(:max_retries) { 3 }

    before do
      allow(client).to receive(:json_post).and_return('choices' =>
        [{ 'index' => 0,
           'message' =>
           { 'role' => 'assistant',
             'tool_calls' => [{ 'id' => 'call_85vQq30Nt8xU1mly2Y2Y1tL2', 'type' => 'function',
                                'function' => { 'name' => 'User', 'arguments' => '\"bad:json\"' } }] } }])
    end

    it 'retries the chat method when parsing fails' do
      expect do
        client.chat(parameters:, response_model: user_model, max_retries:)
      end.to raise_error(JSON::ParserError)

      expect(client).to have_received(:json_post).exactly(max_retries).times
    end
  end

  context 'with validation context' do
    let(:client) { patched_client.new }
    let(:parameters) do
      {
        model: 'gpt-3.5-turbo',
        messages: [
          {
            role: 'user',
            content: 'Answer the question: %<question>s with the text chunk: %<text_chunk>s'
          }
        ]
      }
    end

    it 'returns an object with the expected valid attribute values', vcr: 'patching_spec/with_validation_context' do
      user = client.chat(
        parameters:,
        response_model: user_model,
        validation_context: { question: 'What is your name and age?',
                              text_chunk: 'my name is Jason and I turned 25 years old yesterday' }
      )

      expect(user.name).to eq('Jason')
      expect(user.age).to eq(25)
    end
  end

  context 'with an invalid response model' do
    let(:invalid_model) do
      Class.new do
        include EasyTalk::Model

        def self.name
          'InvalidModel'
        end

        define_schema do
          property :name, String
          property :age, String
        end
      end
    end

    let(:client) { patched_client.new }
    let(:parameters) do
      {
        model: 'gpt-3.5-turbo',
        messages: [{ role: 'user', content: 'Extract Jason is 25 years old' }]
      }
    end

    it 'raises an error when the response model is invalid', vcr: 'patching_spec/invalid_response' do
      expect do
        client.chat(parameters:, response_model: invalid_model)
      end.to raise_error(Instructor::ValidationError)
    end
  end

  describe 'when the client is used ia a standard manner' do
    it 'does not raise an error when the client is used in a standard manner', vcr: 'patching_spec/standard_usage' do
      response = patched_client.new.chat(
        parameters: {
          model: 'gpt-3.5-turbo',
          messages: [{ role: 'user', content: 'How is the weather today in New York?' }]
        }
      )

      expect(response).to be_a(Hash)
      expect(response.dig('choices', 0, 'message', 'content')).to be_a(String)
    end
  end
end
