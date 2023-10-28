# frozen_string_literal: true

class FunctionService
  def self.normal_approval(document)
    @document_approval = DocumentApproval.new(document_id: document.id, approval_status: 0)
    return @document_approval if @document_approval.save

    false
  end

  def self.form_understanding(_document, form_schema_name, _form_model)
    @document = Document.find(params[:id])
    recognizeRes = RestClient.post "#{ENV['DOCAI_ALPHA_URL']}/alpha/form/recognize",
                                   { document_url: @document.storage_url }
    recognizeRes = JSON.parse(recognizeRes)
    puts recognizeRes.inspect
    @form_data = FormDatum.new(data: recognizeRes['recognized_form_data'],
                               form_schema_id: FormSchema.where(name: form_schema_name).first.id, document_id: @document.id)
    return @form_data if @form_data.save

    false
  end
end
