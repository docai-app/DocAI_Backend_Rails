# frozen_string_literal: true

require 'rest-client'

class AirflowService
  @domain = 'https://airflow.m2mda.com'
  @basic_auth = 'Basic YWlyZmxvdzphaXJmbG93'
  @use_ssl = true

  def self.run_dag(dr)
    dag_run = DagRun.find(dr.id) # 強制 reload 一次
    escape_name = CGI.escape(dag_run.dag_name)
    url = URI("#{@domain}/api/v1/dags/#{escape_name}/dagRuns")
    payload = {
      "conf": dag_run['meta']['params'].merge({ response_url: dag_run.response_url,
                                                input_params: dag_run['dag_meta']['input_params'] })
    }
    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = @basic_auth
    request.body = payload.to_json

    response = Net::HTTP.start(url.hostname, url.port, use_ssl: @use_ssl) do |http|
      http.request(request)
    end

    dag_run.update_column(:dag_status, 'in_progress') if response.code == '200'

    JSON.parse(response.body)
  end

  def self.timer_task_callback(date, callback_url)
    url = URI("#{@domain}/api/v1/dags/rails_callback_dag/dagRuns")
    payload = {
      "conf": {
        "start_date": date.to_s,
        "callback_url": callback_url
      }
    }
    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = @basic_auth
    request.body = payload.to_json

    response = Net::HTTP.start(url.hostname, url.port, use_ssl: @use_ssl) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  end
end
