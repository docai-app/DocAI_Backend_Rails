class OpenAiService
  @access_token = ENV["OPENAI_API_ACCESS_TOKEN"]
  @chat_model_id = ENV["OPENAI_API_CHAT_MODEL_ID"]

  def self.chatWithDocument(query, content, response_format, language, topic, style)
    client = OpenAI::Client.new(access_token: @access_token)
    prompt = "You are currently an assistant, and there is a task based on document content generation that requires your assistance. The generated output json must be follow the format (the newline symbol '\n' must be replace to '\\n'!!!) {\"content\": \"\"}. Please help me generate a #{response_format} content about #{topic} using #{language}, and generate it in #{style} style. The generated output json must be follow the format: \'\'\'json\n {\"content\": \"\"} \'\'\'!!! The task is as follows: #{query}, with the reference document as follows: #{content}."
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo", # Required.
        messages: [{ role: "user", content: prompt }], # Required.
        max_tokens: 2048,
        temperature: 0.5,
        top_p: 1,
        frequency_penalty: 0,
        presence_penalty: 0,
      },
    )
    puts "response: #{response["choices"][0]["message"]["content"]}"
    content = Utils.cleansingContentFromGPT(response["choices"][0]["message"]["content"])
    return content
  end
end
