class OpenAiService
  @access_token = ENV["OPENAI_API_ACCESS_TOKEN"]
  @chat_model_id = ENV["OPENAI_API_CHAT_MODEL_ID"]

  def self.chatWithDocument(query, content)
    client = OpenAI::Client.new(access_token: @access_token)
    prompt = "Now you are an efficient assistant, #{query}, The output should follow the format \'\'\'json\n {\"content\": \"\"} \'\'\'!!! and the text content is as follows: #{content}"
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo", # Required.
        messages: [{ role: "user", content: prompt }], # Required.
        max_tokens: 2048,
        temperature: 0.7,
        top_p: 1,
        frequency_penalty: 0,
        presence_penalty: 0,
      },
    )
    puts response["choices"][0]["message"]["content"]
    return response["choices"][0]["message"]["content"]
  end
end
