# frozen_string_literal: true

# Read-only, shared by assignment summaries and grading detail. Never rerun AI,
# rewrite stored results, or turn missing/invalid values into a grade of zero.
class EssayGradingMetrics
  def self.call(grading, category: grading.category)
    new(grading, category).call
  end

  def initialize(grading, category)
    @record = grading
    @category = category
    @grading = object(grading.grading)
    @meta = object(grading.meta)
    @review = object(@meta['teacher_review'])
    @text = object(@grading['data'])['text']
    @raw = parse_object(@text)
  end

  def call
    score, full_score, scores = case @category
                              when 'sentence_builder' then sentence_builder
                              when 'speaking_essay' then speaking_essay
                              when 'sentence_puzzle' then sentence_puzzle
                              when 'speaking_pronunciation' then [number(@record.read_attribute(:score)), 100]
                              when 'comprehension'
                                data = object(@grading['comprehension'])
                                [number(data['score']), number(data['full_score'], data['questions_count'])]
                              when 'listening'
                                data = object(@grading['listening'])
                                [number(data['score']), number(data['full_score'])]
                              else legacy_score
                              end
    {
      metrics_version: 1, score: score, overall_score: score,
      full_score: full_score, the_full_score: full_score, scores: scores || {},
      number_of_suggestion: suggestions
    }
  end

  private

  def object(value)
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def parse_object(value)
    AiJsonParser.object(value).deep_stringify_keys
  rescue JSON::ParserError
    {}
  end

  def number(*values)
    values.each do |value|
      next unless value.is_a?(Numeric) || value.is_a?(String)
      parsed = Float(value, exception: false)
      next unless parsed&.finite?
      return parsed == parsed.to_i ? parsed.to_i : parsed
    end
    nil
  end

  def teacher_score
    object(object(@review['score'])['data'])
  end

  def legacy_score(source = teacher_score.presence || (@text.blank? ? @grading : @raw))
    scores = {}
    if source['criteria'].is_a?(Hash)
      source['criteria'].each do |name, criterion|
        next unless criterion.is_a?(Hash)
        scores[name] = number(criterion['score'], criterion['value'], criterion['points'])
      end
    else
      source.each do |key, criterion|
        next unless key.start_with?('Criterion') && criterion.is_a?(Hash)
        criterion.each do |name, value|
          next if ['Full Score', 'explanation', 'comment', 'feedback'].include?(name)
          scores[name] = number(value)
        end
      end
    end
    [number(source['Overall Score'], source['overall_score'], source['score']),
     number(source['Full Score'], source['full_score']), scores]
  end

  def speaking_essay
    return legacy_score(teacher_score) if teacher_score.present?
    # Match the report locations already supported by the web detail view.
    report = [@grading['report_json'], @grading['speaking_report'], @grading['ielts_speaking_report'],
              @meta['report_json'], @meta['speaking_report'], @meta['ielts_speaking_report']]
             .find { |value| value.is_a?(Hash) }
    merged = @meta.merge(@grading).merge(@raw).merge(object(report))
    candidate = [merged['scores'], merged['speaking_scores'], merged['score_breakdown'],
                 merged['ielts_scores'], merged['scoring'], merged].find { |value| value.is_a?(Hash) }
    candidate = object(candidate)
    overall = number(candidate['overall_band_score'], candidate['overall'],
                     merged['Overall Score'], merged['overall_score'])
    overall ||= number(@record.read_attribute(:score)) if candidate.present? && report.is_a?(Hash)
    full = number(merged['Full Score'], merged['full_score'])
    # Nine is the defined band scale for an actual IELTS speaking score, not a
    # fallback denominator for an absent result.
    full ||= 9 unless overall.nil?
    scores = candidate.slice('fluency_and_coherence', 'lexical_resource',
                             'grammatical_range_and_accuracy', 'pronunciation', 'overall_band_score')
                      .transform_values { |value| number(value) }
    scores['overall_band_score'] = overall unless overall.nil?
    [overall, full, scores]
  end

  def sentence_puzzle
    attempt = [@meta['sentence_puzzle_attempt'], @grading['sentence_puzzle_attempt'],
               object(@grading['meta'])['sentence_puzzle_attempt'], @raw['sentence_puzzle_attempt'],
               @grading['sentence_puzzle']].find { |value| value.is_a?(Hash) }
    return [number(@record.read_attribute(:score)), nil] unless attempt
    [number(attempt['score']), number(attempt['total'], attempt['full_score'])]
  end

  def configured_sentence_count
    # The association is already preloaded by assignment-list callers.
    vocabs = object(@record.essay_assignment&.meta)['vocabs']
    vocabs.length if vocabs.is_a?(Array) && vocabs.any?
  end

  def correctness(sentence)
    return nil unless sentence.is_a?(Hash)
    return sentence['isCorrect'] if [true, false].include?(sentence['isCorrect'])
    return sentence['is_correct'] if [true, false].include?(sentence['is_correct'])
    errors = sentence['errors']
    return nil unless errors.is_a?(Array) || errors.is_a?(Hash)
    errors = errors.values if errors.is_a?(Hash)
    return true if errors.empty?
    return nil unless errors.all? { |error| error.is_a?(Hash) }
    errors.all? { |error| error['error1'].to_s.strip.casecmp?('Correct') }
  end

  def sentence_builder
    native = @grading['sentence_builder']
    native = native.find { |item| item.is_a?(Hash) && !number(item['score']).nil? } if native.is_a?(Array)
    native = object(native)
    teacher_sentences = object(@review['grammar'])['sentences']
    results = @raw['results']
    full = configured_sentence_count || number(native['full_score'])
    sentences = teacher_sentences.is_a?(Array) ? teacher_sentences : results
    if teacher_sentences.is_a?(Array) || number(native['score']).nil?
      return [nil, full] unless sentences.is_a?(Array) && sentences.any?
      full ||= sentences.length
      states = sentences.map { |sentence| correctness(sentence) }
      # A partial/malformed grading is not a completed score with a smaller denominator.
      return [nil, full] if states.any?(&:nil?) || sentences.length != full
      return [states.count(true), full]
    end
    [number(native['score']), full]
  end

  def suggestions
    return nil unless %w[essay sentence_builder speaking_essay speaking_conversation].include?(@category)
    teacher_sentences = object(@review['grammar'])['sentences']
    if teacher_sentences.is_a?(Array)
      return teacher_sentences.sum { |sentence| error_count(object(sentence)['errors']) }
    end
    return number(@grading['number_of_suggestion']) if @text.blank?
    return nil if @raw.empty?
    if @category == 'sentence_builder'
      results = @raw['results']
      return nil unless results.is_a?(Array) && results.any?
      return nil unless results.all? { |result| result.is_a?(Hash) && (result['errors'].is_a?(Array) || result['errors'].is_a?(Hash)) }
      return results.sum { |result| error_count(result['errors']) }
    end
    # No grammar section is different from a valid section with no errors.
    counts = collect_error_counts(@raw)
    counts.any? ? counts.sum : nil
  end

  def error_count(errors)
    values = errors.is_a?(Hash) ? errors.values : errors
    return 0 unless values.is_a?(Array)
    values.count { |error| error.is_a?(Hash) && !error['error1'].to_s.strip.casecmp?('Correct') }
  end

  def collect_error_counts(value)
    return [] unless value.is_a?(Hash)
    value.flat_map do |key, child|
      if key == 'errors' && (child.is_a?(Hash) || child.is_a?(Array))
        [error_count(child)]
      else
        collect_error_counts(child)
      end
    end
  end
end
