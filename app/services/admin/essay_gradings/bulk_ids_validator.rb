# frozen_string_literal: true

module Admin
  module EssayGradings
    # 批量 Admin 操作共用的 ids 参数校验（Rerun / 改状态等）
    class BulkIdsValidator
      MAX_IDS = 5

      ValidationError = Class.new(StandardError)

      # @param ids_param [Object] 来自 params[:ids] 的原始值
      # @return [Array<String>] 去重后的 id 列表
      # @raise [ValidationError] ids 缺失、格式非法或超出上限时抛出
      def self.normalize!(ids_param)
        raise ValidationError, 'ids is required' if ids_param.nil?
        raise ValidationError, 'ids must be an array' unless ids_param.is_a?(Array)
        raise ValidationError, 'ids cannot be empty' if ids_param.empty?

        normalized = ids_param.map(&:to_s).map(&:strip).reject(&:blank?).uniq
        raise ValidationError, 'ids cannot be empty' if normalized.empty?
        raise ValidationError, "ids cannot exceed #{MAX_IDS} items" if normalized.size > MAX_IDS

        normalized
      end
    end
  end
end
