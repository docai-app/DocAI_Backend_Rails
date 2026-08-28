# frozen_string_literal: true

require 'test_helper'

class AiJsonParserTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test 'transport wrappers preserve Unicode, inner backticks, false and zero' do
    original = { 'score' => 0, 'correct' => false, 'text' => '保留 `word` and ```code```' }
    text = original.to_json
    [original, text, "`#{text}`", "``#{text}``", "```json\n#{text}\n```", "```JSON\r\n#{text}\r\n```", "`#{text}", "#{text}".to_json, "\uFEFF#{text}"].each do |input|
      assert_equal original, AiJsonParser.object(input)
    end
    assert_equal original, AiJsonParser.object("```json\n#{text.to_json}\n```" )
  end

  test 'damaged and primitive data are not guessed' do
    [nil, false, 0, 'null', 'false', '0', '[]', '{"score":', '`{"score":1', '```json\nnot valid```'].each do |input|
      assert_raises(JSON::ParserError) { AiJsonParser.object(input) }
    end
  end

  test 'nested decoding is bounded' do
    input = { 'score' => 1 }.to_json
    8.times { input = input.to_json }
    assert_raises(JSON::ParserError) { AiJsonParser.object(input) }
  end
end
