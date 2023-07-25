# frozen_string_literal: true

class AiService
  def self.generateContentByDocuments(query, content, response_format, language, topic, style)
    puts query, content, response_format, language, topic, style
    res = RestClient.post "#{ENV['PORMHUB_URL']}/prompts/docai_documents_generate_content/run.json", { params: {
      query:,
      response_format:,
      language:,
      topic:,
      style:,
      content:
    } }
    res = JSON.parse(res)
    puts "Response from OpenAI: #{res}"
    # puts response["error"].present?
    # if response["error"].present? && response["error"]["code"] == "context_length_exceeded"
    #   return "文件太多了，系統無法處理，請減少文件數量！"
    # end

    # if res.success?
    #   return res.data.content
    # end

    # puts "Response: #{response["choices"][0]["message"]["content"]}"
    # Utils.cleansingContentFromGPT(response['choices'][0]['message']['content'])
    puts res['data']['content']
    res['data']['content']
  end
end
