# frozen_string_literal: true

# Plain text drawing prevents question/answer text being interpreted as HTML.
# Text normalization is display-only; stored questions and scoring stay untouched.
class SupplementPracticePdfContent
  def self.text(value)
    text = value.to_s.dup
    text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::ASCII_8BIT
    text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
  end

  def self.render(pdf, questions:, legacy_text: nil, include_answers: false)
    pdf.move_down 12
    unless questions
      # Genuine legacy prose remains downloadable, with no destructive list-number
      # rewriting (e.g. 3.14 must remain 3.14).
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(filter_html: true), tables: true)
      PrawnHtml.append_html(pdf, markdown.render(text(legacy_text)))
      return
    end

    pdf.text text(questions['quizTitle']), size: 14, style: :bold if questions['quizTitle'].present?
    questions.fetch('sections').each do |section|
      pdf.move_down 14
      pdf.text text(section['topic']), size: 13, style: :bold
      pdf.text text(section['instructions']), size: 11 if section['instructions'].present?
      section.fetch('questions').each_with_index do |question, index|
        prompt = (question['question'] || question['statement']).to_s
        prompt = prompt.gsub("[[#{question['id']}]]", '________') if section['type'] == 'fill_in_the_blanks' && question['id'].present?
        lines = ["#{index + 1}. #{prompt}"]
        lines.concat(question.fetch('options')) if section['type'] == 'multiple_choice'
        lines << 'True / False' if section['type'] == 'true_or_false'
        lines << "Answer: #{question['answer']}" if include_answers
        height = 16 + lines.sum { |line| pdf.height_of(text(line), size: 11, leading: 3, width: pdf.bounds.width - 12) }
        pdf.start_new_page if height < pdf.bounds.height && pdf.cursor < height
        pdf.move_down 10
        pdf.text text("#{index + 1}. #{prompt}"), size: 11, leading: 3
        if section['type'] == 'multiple_choice'
          question.fetch('options').each do |option|
            pdf.text text(option), size: 11, indent_paragraphs: 12, leading: 3
          end
        elsif section['type'] == 'true_or_false'
          pdf.text 'True / False', size: 11, indent_paragraphs: 12
        end
        pdf.text text("Answer: #{question['answer']}"), size: 11, style: :bold if include_answers
      end
    end
  end
end
