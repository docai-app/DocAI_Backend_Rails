# frozen_string_literal: true

module AssignmentPackages
  class PackageScoreSummary
    def self.for(assignment_package)
      new(assignment_package).call
    end

    def initialize(assignment_package)
      @assignment_package = assignment_package
    end

    def call
      item_snapshots = scored_item_snapshots
      raw_scores = item_snapshots.filter_map { |snapshot| snapshot[:score] }
      normalized_scores = item_snapshots.filter_map do |snapshot|
        normalize_to_100(snapshot[:score], snapshot[:full_score])
      end

      {
        total_score: normalized_average(normalized_scores),
        full_score: 100,
        average_score: raw_average(raw_scores),
        scored_items: raw_scores.size,
        total_items: @assignment_package.assignment_package_items.size,
        completed_at: package_completed_at
      }
    end

    private

    def normalize_to_100(score, full_score)
      return nil if score.nil?

      denominator = full_score.present? && full_score.to_f.positive? ? full_score.to_f : 100.0
      ((score.to_f / denominator) * 100).round(1)
    end

    def normalized_average(scores)
      return nil if scores.empty?

      (scores.sum.to_f / scores.size).round(1)
    end

    def raw_average(scores)
      return nil if scores.empty?

      (scores.sum.to_f / scores.size).round(1)
    end

    def scored_item_snapshots
      @assignment_package.assignment_package_items.includes(:essay_assignment, :essay_grading).filter_map do |item|
        grading = item.display_grading
        next unless grading

        snapshot = GradingScoreSnapshot.for(
          grading,
          category: item.category.presence || grading.essay_assignment&.category
        )
        next if snapshot[:score].nil?

        snapshot
      end
    end

    def package_completed_at
      @assignment_package.assignment_package_items.maximum(:completed_at) || @assignment_package.updated_at
    end
  end
end
