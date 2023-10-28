# frozen_string_literal: true

module Api
  module V1
    class DagRunsController < ApiController
      before_action :set_dag_run, except: %i[create index]

      # 不限 user 可以使用
      def api_user
        nil
      end

      def index
        drs = DagRun.where(user: api_user).order(created_at: :desc)
        json_success(drs.as_json(only: %i[id dag_name dag_status created_at updated_at]))
      end

      def show
        json_success(@dag_run)
      end

      def check_status_finish
        json_success(@dag_run.check_status_finish)
      end

      def create
        dr = DagRun.new(user: api_user, dag_name: Dag.normalize_name(params[:dag_name]))
        dr['meta']['params'] = params.permit!.to_h['params']
        if dr.save
          dr.reset_workflow!
          dr.start
          json_success(dr)
        else
          json_fail
        end
      end

      # 呢個係一個 callback function, 用黎比 airflow 更新狀態
      # {task_name: 'task1', content: {}}

      def update
        @dag_run.find_status_stack_by_key(params[:task_name])
        obj = { task_name: params[:task_name], content: params[:content] }
        @dag_run.add_or_replace_status_stack(obj)
        @dag_run.dag_status_check!

        json_success
      end

      protected

      def set_dag_run
        @dag_run = DagRun.find(params[:id])
      end
    end
  end
end
