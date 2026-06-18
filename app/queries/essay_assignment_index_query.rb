# frozen_string_literal: true

class EssayAssignmentIndexQuery
  Result = Struct.new(:assignments, :meta, keyword_init: true)

  LIST_SELECT = <<~SQL.squish
    essay_assignments.id,
    essay_assignments.rubric,
    essay_assignments.title,
    essay_assignments.hints,
    essay_assignments.category,
    essay_assignments.answer_visible,
    essay_assignments.topic,
    essay_assignments.created_at,
    essay_assignments.updated_at,
    essay_assignments.code,
    essay_assignments.assignment,
    essay_assignments.number_of_submission,
    essay_assignments.general_user_id,
    #{EssayAssignment.list_meta_sql_select}
  SQL

  def initialize(user:, category: nil, page: 1, per: 10)
    @user = user
    @category = category.presence
    @page = [page.to_i, 1].max
    @per = per.to_i.positive? ? per.to_i : 10
  end

  def call
    assignments = combined_relation.offset(offset).limit(@per).to_a
    preload_general_users!(assignments)

    Result.new(
      assignments: assignments,
      meta: pagination_meta
    )
  end

  private

  def combined_relation
    EssayAssignment
      .unscoped
      .from(Arel.sql("(#{union_sql}) AS ea_merged"))
      .select(Arel.sql('ea_merged.*'))
      .order(Arel.sql('ea_merged.updated_at DESC'))
  end

  def union_sql
    "#{owned_scope.to_sql} UNION ALL #{shared_scope.to_sql}"
  end

  def owned_scope
    scope = EssayAssignment.where(general_user_id: @user.id)
    scope = scope.where(category: @category) if @category.present?
    scope.select(Arel.sql("#{LIST_SELECT}, 'owner' AS list_access_type"))
  end

  def shared_scope
    scope = EssayAssignment
            .joins(:active_essay_assignment_shares)
            .where(essay_assignment_shares: { shared_with_general_user_id: @user.id })

    scope = apply_shared_category_filter(scope)
    scope.select(Arel.sql("#{LIST_SELECT}, 'shared' AS list_access_type"))
  end

  def apply_shared_category_filter(scope)
    allowed_categories = Array(@user.aienglish_features_list).compact + ['sentence_puzzle']

    if @category.present?
      return scope.none if allowed_categories.exclude?(@category)

      return scope.where(category: @category)
    end

    return scope.none if allowed_categories.empty?

    scope.where(category: allowed_categories)
  end

  def total_count
    owned_count + shared_count
  end

  def owned_count
    scope = EssayAssignment.where(general_user_id: @user.id)
    scope = scope.where(category: @category) if @category.present?
    scope.count
  end

  def shared_count
    scope = EssayAssignment
            .joins(:active_essay_assignment_shares)
            .where(essay_assignment_shares: { shared_with_general_user_id: @user.id })
    apply_shared_category_filter(scope).count
  end

  def offset
    (@page - 1) * @per
  end

  def total_pages
    return 0 if total_count.zero?

    (total_count.to_f / @per).ceil
  end

  def pagination_meta
    {
      current_page: @page,
      next_page: @page < total_pages ? @page + 1 : nil,
      prev_page: @page > 1 ? @page - 1 : nil,
      total_pages: total_pages,
      total_count: total_count
    }
  end

  def preload_general_users!(assignments)
    ActiveRecord::Associations::Preloader.new(
      records: assignments,
      associations: [:general_user]
    ).call
  end
end
