# frozen_string_literal: true

require 'openai'
require 'anthropic'
require 'easy_talk'
require 'active_support/all'
require_relative 'instructor/version'
require_relative 'instructor/openai/patch'
require_relative 'instructor/openai/response'
require_relative 'instructor/mode'

# Instructor makes it easy to reliably get structured data like JSON from Large Language Models (LLMs)
# like GPT-3.5, GPT-4, GPT-4-Vision
module Instructor
  @mode = nil

  class Error < ::StandardError; end

  # The ValidationError class represents an error that occurs during validation.
  class ValidationError < ::StandardError; end

  def self.mode
    @mode
  end

  # Patches the OpenAI client to add the following functionality:
  # - Retries on exceptions
  # - Accepts and validates a response model
  # - Accepts a validation_context argument
  #
  # @param openai_client [OpenAI::Client] The OpenAI client to be patched.
  # @param mode [Symbol] The mode to be used. Default is `Instructor::Mode::TOOLS.function`.
  # @return [OpenAI::Client] The patched OpenAI client.
  def self.patch(openai_client, mode: Instructor::Mode::TOOLS.function)
    @mode = mode
    openai_client.prepend(Instructor::OpenAI::Patch)
  end
end
