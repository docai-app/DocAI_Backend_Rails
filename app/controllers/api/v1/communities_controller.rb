# frozen_string_literal: true

class Api::V1::CommunitiesController < ApplicationController
  before_action :authenticate_general_user!
  before_action :set_community, only: [:show, :update, :destroy, :join, :leave, :members, :stats, :essay_assignments]

  # GET /api/v1/communities
  # 获取当前用户的所有Communities（创建的和加入的）
  def index
    @communities = current_general_user.accessible_communities
                                      .includes(:general_user, :community_memberships, :essay_assignments)
                                      .order(created_at: :desc)
    @communities = Kaminari.paginate_array(@communities).page(params[:page])
    
    # 构建包含统计信息的响应数据
    communities_with_stats = @communities.map do |community|
      community_json(community)
    end
    
    render json: { success: true, communities: communities_with_stats, meta: pagination_meta(@communities) },
               status: :ok
  end

  # GET /api/v1/communities/:id
  # 获取单个Community详情
  def show
    unless can_access_community?(@community)
      return render json: { success:false, status: 'error', message: 'Access denied' }, status: :forbidden
    end
    render json: { success: true, community: community_detail_json(@community) }
  end

  # POST /api/v1/communities
  # 创建新的Community
  def create
    @community = current_general_user.created_communities.build(community_params)

    if @community.save
      render json: { success: true, community: community_json(@community) }, status: :created
    else
      render json: { success: false, errors: @community.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/communities/:id
  # 更新Community（仅创建者可以）
  def update
    unless @community.creator?(current_general_user)
      return render json: { success:false, status: 'error', message: 'Only the creator can update this community' }, 
                    status: :forbidden
    end

    if @community.update(community_params)
      render json: {
        success: true,
        message: 'Community updated successfully',
        data: community_json(@community)
      }
    else
      render json: {
        success: false,
        message: 'Failed to update community',
        errors: @community.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/communities/:id
  # 删除Community（仅创建者可以）
  def destroy
    unless @community.creator?(current_general_user)
      return render json: {success: false, status: 'error', message: 'Only the creator can delete this community' }, 
                    status: :forbidden
    end

    if @community.destroy
      render json: {
        success: true,
        status: 'success',
        message: 'Community deleted successfully'
      }
    else
      render json: {
        success: false,
        status: 'error',
        message: 'Failed to delete community'
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/communities/join
  # 通过code加入Community
  def join_by_code
    code = params[:code]&.strip&.upcase
    
    if code.blank?
      return render json: {success: false, status: 'error', message: 'Code is required' }, status: :bad_request
    end

    result = current_general_user.join_community(code)
    
    if result[:success]
      render json: {
        success: true,
        status: 'success',
        message: 'Successfully joined the community',
        data: community_json(result[:community])
      }
    else
      render json: {
           success: false,
        status: 'error',
        message: result[:error]
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/communities/:id/leave
  # 离开Community
  def leave
    unless @community.member?(current_general_user)
      return render json: { success: false,status: 'error', message: 'You are not a member of this community' }, 
                    status: :bad_request
    end

    if @community.creator?(current_general_user)
      return render json: { success: false,status: 'error', message: 'Creator cannot leave their own community' }, 
                    status: :bad_request
    end

    @community.remove_member(current_general_user)
    render json: {
      success: true,
      status: 'success',
      message: 'Successfully left the community'
    }
  end

  # GET /api/v1/communities/:id/members
  # 获取Community成员列表（仅成员或创建者可查看）
  def members
    unless can_access_community?(@community)
      return render json: { success: false,status: 'error', message: 'Access denied' }, status: :forbidden
    end

    members = @community.community_memberships
                       .includes(:general_user)
                       .order(:created_at)

    render json: {
      success: true, 
      data: {
        community: community_json(@community),
        members: members.map { |membership| member_json(membership) }
      }
    }
  end

  # GET /api/v1/communities/:id/stats
  # 获取Community统计信息（仅创建者可查看）
  def stats
    unless @community.creator?(current_general_user)
      return render json: { success: false,status: 'error', message: 'Only the creator can view statistics' }, 
                    status: :forbidden
    end

    render json: {
      success: true,
      status: 'success',
      data: @community.stats
    }
  end

  # GET /api/v1/communities/:id/essay_assignments
  # 获取Community下的所有EssayAssignment
  def essay_assignments
    unless can_access_community?(@community)
      return render json: {success: false, status: 'error', message: 'Access denied' }, status: :forbidden
    end

    essay_assignments = @community.essay_assignments
                                  .includes(:general_user)
                                  .order(created_at: :desc)

    # 添加分类筛选
    if params[:category].present?
      essay_assignments = essay_assignments.where(category: params[:category])
    end

    # 分页
    page = params[:page] || 1
    per_page = params[:per_page] || 20
    essay_assignments = essay_assignments.limit(per_page).offset((page.to_i - 1) * per_page.to_i)

    assignments_data = essay_assignments.map do |assignment|
      {
        id: assignment.id,
        title: assignment.title,
        topic: assignment.topic,
        category: assignment.category,
        code: assignment.code,
        hints: assignment.hints,
        answer_visible: assignment.answer_visible,
        number_of_submission: assignment.number_of_submission,
        created_at: assignment.created_at,
        updated_at: assignment.updated_at,
        creator: {
          id: assignment.general_user.id,
          nickname: assignment.general_user.nickname,
          email: assignment.general_user.email
        }
      }
    end

    render json: {
      success: true,
      status: 'success',
      data: {
        community: {
          id: @community.id,
          name: @community.name,
          code: @community.code,
          description: @community.description
        },
        essay_assignments: assignments_data,
        meta: {
          total_count: @community.essay_assignments.count,
          page: page.to_i,
          per_page: per_page.to_i
        }
      }
    }
  end

  # GET /api/v1/communities/search
  # 通过code搜索Community
  def search_by_code
    code = params[:code]&.strip&.upcase
    
    if code.blank?
      return render json: { status: 'error', message: 'Code is required' }, status: :bad_request
    end

    community = Community.find_by_code(code)
    
    if community
      render json: {
        success: true,
        status: 'success',
        data: {
          id: community.id,
          name: community.name,
          description: community.description,
          code: community.code,
          creator: {
            id: community.general_user.id,
            nickname: community.general_user.nickname
          },
          members_count: community.members_count,
          can_join: !community.member?(current_general_user) && !community.creator?(current_general_user)
        }
      }
    else
      render json: {
        success: false,
        status: 'error',
        message: 'Community not found'
      }, status: :not_found
    end
  end

  private

  def set_community
    @community = Community.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {success: false, status: 'error', message: 'Community not found' }, status: :not_found
  end

  def community_params
    params.require(:community).permit(:name, :description, :cover)
  end

  def can_access_community?(community)
    community.creator?(current_general_user) || community.member?(current_general_user)
  end

  def community_json(community)
    {
      id: community.id,
      name: community.name,
      description: community.description,
      code: community.code,
      cover_url: community.cover_url,
      creator: {
        id: community.general_user.id,
        nickname: community.general_user.nickname,
        email: community.general_user.email
      },
      members_count: community.members_count,
      essay_assignments_count: community.essay_assignments_count,
      is_creator: community.creator?(current_general_user),
      is_member: community.member?(current_general_user),
      created_at: community.created_at,
      updated_at: community.updated_at
    }
  end

  def community_detail_json(community)
    base_json = community_json(community)
    
    # 添加最近的作业
    recent_assignments = community.essay_assignments
                                .includes(:general_user)
                                .order(created_at: :desc)
                                .limit(5)

    base_json[:recent_essay_assignments] = recent_assignments.map do |assignment|
      {
        id: assignment.id,
        title: assignment.title,
        topic: assignment.topic,
        category: assignment.category,
        code: assignment.code,
        created_at: assignment.created_at,
        creator: {
          id: assignment.general_user.id,
          nickname: assignment.general_user.nickname
        }
      }
    end

    base_json
  end

  def member_json(membership)
    {
      id: membership.id,
      user: {
        id: membership.general_user.id,
        nickname: membership.general_user.nickname,
        email: membership.general_user.email
      },
      role: membership.role,
      joined_at: membership.joined_at || membership.created_at,
      created_at: membership.created_at
    }
  end

  def pagination_meta(object)
        {
          current_page: object.current_page,
          next_page: object.next_page,
          prev_page: object.prev_page,
          total_pages: object.total_pages,
          total_count: object.total_count
        }
      end
end