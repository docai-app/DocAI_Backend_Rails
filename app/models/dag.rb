# frozen_string_literal: true

# == Schema Information
#
# Table name: dags
#
#  id         :bigint(8)        not null, primary key
#  name       :string
#  meta       :jsonb
#  user_id    :bigint(8)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_dags_on_name     (name)
#  index_dags_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'net/scp'
require 'net/ssh'
require 'tempfile'
class Dag < ApplicationRecord
  store_accessor :meta # , :original_name

  belongs_to :user

  before_save :name_no_space
  after_save :sync_to_airflow

  # 使用呢個 function, 將呢個 dag 同步到去 airflow
  before_destroy :remove_dag_from_airflow

  def name_no_space
    # special_chars_regex = /[<>\/\\|:"*?()']/
    # self['name'] = self['name'].gsub(/\s+/, '_').gsub(special_chars_regex, '')
    self['name'] = Dag.normalize_name(self['name'])
  end

  def self.normalize_name(name)
    special_chars_regex = %r{[<>/\\|:"*?()']}
    name.gsub(/\s+/, '_').gsub(special_chars_regex, '')
  end

  def sync_to_airflow
    # {input: sfsf} 變成 [input: sfsf]
    wf = self['meta']['workflow'].transform_values do |value|
      value['prompt'] = value['prompt'].gsub(/\{([^{}]+)\}(?!\})/, '[\\1]') if value.key?('prompt')
      value
    end

    json_string = { name:, workflow: wf }.to_json
    json_string = json_string.gsub(/\{\{\s*(.*?)\s*\}\}/, '{\1}') # {{background}} 變成 {background}
    # binding.pry
    tempfile = Tempfile.new("#{name}.json")

    # 寫入 JSON 字符串到臨時文件
    tempfile.write(json_string)
    tempfile.close

    # 傳送文件到遠程服務器
    dag_file_path_on_remote = "/home/akali/airflow_docker/dag_json_configs/#{name}.json"
    Net::SSH.start(ENV['airflow_host'], ENV['airflow_host_user_name'], password: ENV['airflow_host_user_pass']) do |ssh|
      ssh.scp.upload!(tempfile.path, dag_file_path_on_remote)
      puts '完成上傳'

      # 组合切换目录和执行脚本的命令字符串
      command = "cd /home/akali/airflow_docker && bash /home/akali/airflow_docker/import_dag_json.sh #{dag_file_path_on_remote}"

      # 执行命令字符串
      result = ssh.exec!(command)

      # 处理命令执行结果
      puts result
    end

    tempfile.unlink
  end

  def remove_dag_from_airflow
    dag_file_path_on_remote = "/home/akali/airflow_docker/dag_json_configs/#{name}.json"
    Net::SSH.start(ENV['airflow_host'], ENV['airflow_host_user_name'], password: ENV['airflow_host_user_pass']) do |ssh|
      # 组合切换目录和执行脚本的命令字符串
      command = "cd /home/akali/airflow_docker && bash /home/akali/airflow_docker/remove_dag_json.sh #{dag_file_path_on_remote}"

      # 执行命令字符串
      result = ssh.exec!(command)

      # 处理命令执行结果
      puts result
    end
  end

  def input_params
    return if self['meta']['workflow'].nil?

    r = {}
    self['meta']['workflow'].each do |k, v|
      r[k] = v['input_params']
    end
    r
  end
end
