class OpenAiService
  @access_token = ENV["OPENAI_API_ACCESS_TOKEN"]
  @chat_model_id = ENV["OPENAI_API_CHAT_MODEL_ID"]

  def self.chatWithDocument(query, content, response_format, language, topic, style)
    client = OpenAI::Client.new(access_token: @access_token)
    # prompt = "Now you are an efficient assistant and you have a mission is about writting an #{style} style #{format} by using #{language}. #{query}, The output should follow the format \'\'\'json\n {\"content\": \"\"} \'\'\'!!! and the text content is as follows: #{content}"
    prompt = "You are currently an assistant, and there is a task based on document content generation that requires your assistance. Please help me generate a #{response_format} content about #{topic} using #{language}, and generate it in #{style} style. The output should follow this json format \'\'\'json\n {\"content\": \"\"} \'\'\' json object!!! The task is as follows: #{query}, with the reference document as follows: #{content}."
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
    content = Utils.cleansingContentFromGPT(response["choices"][0]["message"]["content"])
    return content
  end
end
