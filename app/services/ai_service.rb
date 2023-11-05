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

  def self.documentSmartExtraction(schema, content, storage_url, data_schema)
    puts "DocumentSmartExtraction: #{schema}, #{content}, #{storage_url} #{data_schema}"
    if schema.first['query'].is_a?(Array)
      puts "DocumentSmartExtraction: Array Task!"
      res = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/smart_extraction_schema/map_reduce", { storage_url: storage_url, schema: schema, data_schema: data_schema }, timeout: 3000
      puts "Res: #{res}"
    else
      res = RestClient.post "#{ENV['PORMHUB_URL']}/prompts/docai_document_smart_extraction/run.json", { params: {
        schema:,
        content:,
        data_schema:
      } }
      res = JSON.parse(res)
      puts "Response from OpenAI: #{res}"
      res['data']
  end

  def self.assistantQA(query, chat_history, schema, metadata)
    res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/documents/embedding/qa", {
      query:,
      chat_history:,
      schema:,
      metadata:
    }.to_json, { content_type: :json, accept: :json })
    res = JSON.parse(res)
    puts "Response from Document Embedding QA: #{res}"
    if res['status'] == true
      res
    else
      res['message']
    end
  end

  def self.assistantQASuggestion(schema, metadata)
    res = RestClient.post("#{ENV['DOCAI_ALPHA_URL']}/documents/embedding/qa/suggestion", {
      schema:,
      metadata:
    }.to_json, { content_type: :json, accept: :json })
    res = JSON.parse(res)
    puts "Response from Document Embedding QA Suggestion: #{res}"
    if res['status'] == true
      res['suggestion']
    else
      res['message']
    end
  end
end
