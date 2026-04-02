# frozen_string_literal: true

module Api
  module Admin
    module V1
      class EssayAssignmentsController < ApplicationController
        # before_action :authenticate_user! # 管理员认证
        before_action :set_essay_assignment, only: [:show, :update, :submissions]

        # 作业概览统计
        # GET /api/admin/v1/essay_assignments/overview
        def overview
          total_assignments = EssayAssignment.count
          
          # 各类别统计
          category_stats = EssayAssignment.group(:category)
                                         .count
                                         .transform_keys { |k| k.humanize }
          
          # 计算百分比
          category_percentages = category_stats.transform_values do |count|
            total_assignments > 0 ? (count.to_f / total_assignments * 100).round(2) : 0
          end
          
          # 最近30天创建的作业数量
          recent_assignments = EssayAssignment.where('essay_assignments.created_at >= ?', 30.days.ago).count
          
          # 总提交数量
          total_submissions = EssayGrading.count
          
          # 各状态提交统计
          submission_stats = EssayGrading.group(:status).count
          
          # 最活跃的作业（按提交数量排序）
          top_assignments = EssayAssignment.joins(:essay_gradings)
                                          .group('essay_assignments.id, essay_assignments.title, essay_assignments.topic')
                                          .order('COUNT(essay_gradings.id) DESC')
                                          .limit(5)
                                          .pluck(
                                            'essay_assignments.id',
                                            'essay_assignments.title', 
                                            'essay_assignments.topic',
                                            'COUNT(essay_gradings.id)'
                                          )
                                          .map do |id, title, topic, count|
                                            {
                                              id: id,
                                              title: title,
                                              topic: topic,
                                              submissions_count: count
                                            }
                                          end
          
          render json: {
            success: true,
            data: {
              overview: {
                total_assignments: total_assignments,
                total_submissions: total_submissions,
                recent_assignments: recent_assignments,
                category_stats: category_stats,
                category_percentages: category_percentages,
                submission_stats: submission_stats,
                top_assignments: top_assignments
              }
            }
          }, status: :ok
        end

        # 作业列表管理
        # GET /api/admin/v1/essay_assignments
        def index
          @essay_assignments = EssayAssignment.includes(:general_user, :essay_gradings)
          
          # 搜索过滤
          if params[:search].present?
            search_term = "%#{params[:search]}%"
            @essay_assignments = @essay_assignments.joins(:general_user)
                                                  .where(
                                                    'essay_assignments.topic ILIKE ? OR essay_assignments.title ILIKE ? OR essay_assignments.assignment ILIKE ? OR essay_assignments.code ILIKE ? OR general_users.nickname ILIKE ? OR general_users.email ILIKE ?',
                                                    search_term, search_term, search_term, search_term, search_term, search_term
                                                  )
          end
          
          # 类别过滤
          if params[:category].present?
            @essay_assignments = @essay_assignments.where(category: params[:category])
          end
          
          # 创建者过滤
          if params[:creator_id].present?
            @essay_assignments = @essay_assignments.where(general_user_id: params[:creator_id])
          end
          
          # 日期范围过滤
          if params[:start_date].present?
            @essay_assignments = @essay_assignments.where('essay_assignments.created_at >= ?', Date.parse(params[:start_date]))
          end
          
          if params[:end_date].present?
            @essay_assignments = @essay_assignments.where('essay_assignments.created_at <= ?', Date.parse(params[:end_date]).end_of_day)
          end
          
          # 排序
          sort_by = params[:sort_by] || 'created_at'
          sort_order = params[:sort_order] || 'desc'
          
          case sort_by
          when 'submissions_count'
            @essay_assignments = @essay_assignments.left_joins(:essay_gradings)
                                                  .group('essay_assignments.id')
                                                  .order("COUNT(essay_gradings.id) #{sort_order}")
          when 'creator'
            @essay_assignments = @essay_assignments.joins(:general_user)
                                                  .order("general_users.nickname #{sort_order}")
          else
            # 明确指定表名以避免字段歧义
            table_prefix = case sort_by
                          when 'created_at', 'updated_at'
                            'essay_assignments.'
                          else
                            ''
                          end
            @essay_assignments = @essay_assignments.order("#{table_prefix}#{sort_by} #{sort_order}")
          end
          
          # 分页
          page = params[:page] || 1
          per_page = params[:per_page] || 20
          @essay_assignments = @essay_assignments.page(page).per(per_page)
          
          # 构建响应数据
          assignments_data = @essay_assignments.map do |assignment|
            {
              id: assignment.id,
              title: assignment.title,
              topic: assignment.topic,
              assignment: assignment.assignment,
              category: assignment.category,
              code: assignment.code,
              answer_visible: assignment.answer_visible,
              remark: assignment.remark,
              created_at: assignment.created_at,
              updated_at: assignment.updated_at,
              submissions_count: assignment.essay_gradings.count,
              creator: {
                id: assignment.general_user.id,
                nickname: assignment.general_user.nickname,
                email: assignment.general_user.email
              },
              community: assignment.community ? {
                id: assignment.community.id,
                name: assignment.community.name,
                code: assignment.community.code
              } : nil,
              meta: assignment.meta,
              rubric: assignment.rubric
            }
          end
          
          render json: {
            success: true,
            data: {
              assignments: assignments_data,
              pagination: {
                current_page: @essay_assignments.current_page,
                total_pages: @essay_assignments.total_pages,
                total_count: @essay_assignments.total_count,
                per_page: per_page.to_i
              }
            }
          }, status: :ok
        end

        # 作业详情
        # GET /api/admin/v1/essay_assignments/:id
        def show
          # 获取提交统计
          submissions_stats = @essay_assignment.essay_gradings
                                              .group(:status)
                                              .count
          
          # 最近提交记录
          recent_submissions = @essay_assignment.essay_gradings
                                               .includes(:general_user)
                                               .order('essay_gradings.created_at DESC')
                                               .limit(10)
                                               .map do |grading|
                                                 {
                                                   id: grading.id,
                                                   status: grading.status,
                                                   created_at: grading.created_at,
                                                   student: {
                                                     id: grading.general_user.id,
                                                     nickname: grading.general_user.nickname,
                                                     email: grading.general_user.email
                                                   },
                                                   score: grading.score,
                                                   using_time: grading.using_time
                                                 }
                                               end
          
          # 按日期统计提交量（最近30天）
          daily_submissions = @essay_assignment.essay_gradings
                                              .where('essay_gradings.created_at >= ?', 30.days.ago)
                                              .group("DATE(essay_gradings.created_at)")
                                              .count
          
          assignment_data = {
            id: @essay_assignment.id,
            title: @essay_assignment.title,
            topic: @essay_assignment.topic,
            assignment: @essay_assignment.assignment,
            category: @essay_assignment.category,
            code: @essay_assignment.code,
            answer_visible: @essay_assignment.answer_visible,
            remark: @essay_assignment.remark,
            hints: @essay_assignment.hints,
            created_at: @essay_assignment.created_at,
            updated_at: @essay_assignment.updated_at,
            creator: {
              id: @essay_assignment.general_user.id,
              nickname: @essay_assignment.general_user.nickname,
              email: @essay_assignment.general_user.email
            },
            community: @essay_assignment.community ? {
              id: @essay_assignment.community.id,
              name: @essay_assignment.community.name,
              code: @essay_assignment.community.code
            } : nil,
            meta: @essay_assignment.meta,
            rubric: @essay_assignment.rubric,
            graph_image_url: @essay_assignment.graph_image_url,
            statistics: {
              total_submissions: @essay_assignment.essay_gradings.count,
              submissions_stats: submissions_stats,
              recent_submissions: recent_submissions,
              daily_submissions: daily_submissions
            }
          }
          
          render json: {
            success: true,
            data: { assignment: assignment_data }
          }, status: :ok
        end

        # 作业提交列表
        # GET /api/admin/v1/essay_assignments/:id/submissions
        def submissions
          @submissions = @essay_assignment.essay_gradings.includes(:general_user)
          
          # 状态过滤
          if params[:status].present?
            @submissions = @submissions.where(status: params[:status])
          end
          
          # 学生搜索
          if params[:student_search].present?
            search_term = "%#{params[:student_search]}%"
            @submissions = @submissions.joins(:general_user)
                                      .where(
                                        'general_users.nickname ILIKE ? OR general_users.email ILIKE ?',
                                        search_term, search_term
                                      )
          end
          
          # 日期范围过滤
          if params[:start_date].present?
            @submissions = @submissions.where('essay_gradings.created_at >= ?', Date.parse(params[:start_date]))
          end
          
          if params[:end_date].present?
            @submissions = @submissions.where('essay_gradings.created_at <= ?', Date.parse(params[:end_date]).end_of_day)
          end
          
          # 排序
          sort_by = params[:sort_by] || 'created_at'
          sort_order = params[:sort_order] || 'desc'
          
          case sort_by
          when 'student_name'
            @submissions = @submissions.joins(:general_user)
                                      .order("general_users.nickname #{sort_order}")
          when 'score'
            @submissions = @submissions.order("score #{sort_order}")
          else
            # 明确指定表名以避免字段歧义
            table_prefix = case sort_by
                          when 'created_at', 'updated_at'
                            'essay_gradings.'
                          else
                            ''
                          end
            @submissions = @submissions.order("#{table_prefix}#{sort_by} #{sort_order}")
          end
          
          # 分页
          page = params[:page] || 1
          per_page = params[:per_page] || 20
          @submissions = @submissions.page(page).per(per_page)
          
          # 构建响应数据
          submissions_data = @submissions.map do |submission|
            {
              id: submission.id,
              status: submission.status,
              score: submission.score,
              using_time: submission.using_time,
              created_at: submission.created_at,
              updated_at: submission.updated_at,
              student: {
                id: submission.general_user.id,
                nickname: submission.general_user.nickname,
                email: submission.general_user.email,
                class_name: submission.general_user.banbie,
                class_no: submission.general_user.class_no
              },
              submission_class_name: submission.submission_class_name,
              submission_class_number: submission.submission_class_number,
              meta: submission.meta
            }
          end
          
          render json: {
            success: true,
            data: {
              submissions: submissions_data,
              pagination: {
                current_page: @submissions.current_page,
                total_pages: @submissions.total_pages,
                total_count: @submissions.total_count,
                per_page: per_page.to_i
              }
            }
          }, status: :ok
        end

        # 更新作业信息
        # PATCH/PUT /api/admin/v1/essay_assignments/:id
        def update
          if @essay_assignment.update(essay_assignment_update_params)
            render json: {
              success: true,
              message: 'Assignment updated successfully',
              data: {
                assignment: {
                  id: @essay_assignment.id,
                  title: @essay_assignment.title,
                  topic: @essay_assignment.topic,
                  assignment: @essay_assignment.assignment,
                  category: @essay_assignment.category,
                  code: @essay_assignment.code,
                  answer_visible: @essay_assignment.answer_visible,
                  remark: @essay_assignment.remark,
                  hints: @essay_assignment.hints,
                  updated_at: @essay_assignment.updated_at,
                  meta: @essay_assignment.meta,
                  rubric: @essay_assignment.rubric
                }
              }
            }, status: :ok
          else
            render json: {
              success: false,
              message: 'Failed to update assignment',
              errors: @essay_assignment.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # 获取可用的类别列表
        # GET /api/admin/v1/essay_assignments/categories
        def categories
          categories_list = EssayAssignment.categories.keys.map do |category|
            {
              value: category,
              label: category.humanize,
              count: EssayAssignment.where(category: category).count
            }
          end
          
          render json: {
            success: true,
            data: { categories: categories_list }
          }, status: :ok
        end

        # 获取创建者列表
        # GET /api/admin/v1/essay_assignments/creators
        def creators
          creators_list = GeneralUser.joins(:essay_assignments)
                                    .distinct
                                    .select(:id, :nickname, :email)
                                    .map do |user|
                                      {
                                        id: user.id,
                                        nickname: user.nickname,
                                        email: user.email,
                                        assignments_count: user.essay_assignments.count
                                      }
                                    end
          
          render json: {
            success: true,
            data: { creators: creators_list }
          }, status: :ok
        end

        private

        def set_essay_assignment
          @essay_assignment = EssayAssignment.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: {
            success: false,
            message: 'Assignment not found'
          }, status: :not_found
        end

        def essay_assignment_update_params
          params.require(:essay_assignment).permit(
            :title,
            :topic,
            :assignment,
            :answer_visible,
            :remark,
            :hints,
            meta: {},
            rubric: {}
          )
        end
      end
    end
  end
end